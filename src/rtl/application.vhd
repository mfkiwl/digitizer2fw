library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.communication_pkg.all;
use work.sampling_pkg.all;
use work.tdc_sample_prep_pkg.all;

entity application is
port (
    clk_main: in std_logic;
    clk_samples: in std_logic;
    LED1: out std_logic;
    LED2: out std_logic;
    device_temp: in std_logic_vector(11 downto 0);

    -- usb communication
    comm_addr: in unsigned(5 downto 0);
    comm_port: in unsigned(5 downto 0);
    comm_to_slave: in comm_to_slave_t;
    comm_from_slave: out comm_from_slave_t;
    comm_error: in std_logic;

    -- ram interface
    ram_calib_complete : in  std_logic;
    ram_rdy            : in  std_logic;
    ram_addr           : out std_logic_vector(27 downto 0);
    ram_cmd            : out std_logic_vector(2 downto 0);
    ram_en             : out std_logic;
    ram_rd_data        : in  std_logic_vector(127 downto 0);
    ram_rd_data_valid  : in  std_logic;
    ram_wdf_rdy        : in  std_logic;
    ram_wdf_data       : out std_logic_vector(127 downto 0);
    ram_wdf_wren       : out std_logic;
    ram_wdf_end        : out std_logic;

    -- analog pwr/enable/rst
    APWR_EN: out std_logic;
    ADC_ENABLE: out std_logic;
    ADC_SRESETB: out std_logic;

    -- adc program
    adc_prog_start: out std_logic;
    adc_prog_rd: out std_logic;
    adc_prog_busy: in std_logic;
    adc_prog_addr: out std_logic_vector(6 downto 0);
    adc_prog_din: out std_logic_vector(15 downto 0);
    adc_prog_dout: in std_logic_vector(15 downto 0);

    -- analog/digital samples
    sampling_rst: out std_logic;
    samples_d: in din_samples_t(0 to 3);
    samples_a: in adc_samples_t(0 to 1)
);
end application;

architecture application_arch of application is

    -- clock domain crossing
    component slow_cdc_bit
    port (clk: in std_logic; din: in std_logic; dout: out std_logic);
    end component;
    component slow_cdc_bits
    port (clk: in std_logic; din: in std_logic_vector; dout: out std_logic_vector);
    end component;

    -- sample processing for TDC
    constant TDC_CNT_BITS: natural := 22;
    signal tdc_a_invert : std_logic := '0';
    signal tdc_a_average : std_logic_vector(1 downto 0) := (others => '0');
    signal tdc_a_threshold_cd1, tdc_a_threshold_cd2: a_sample_t := (others => '0');
    signal tdc_a_threshold_cd2slv: std_logic_vector(a_sample_t'range) := (others => '0');
    signal tdc_d : din_samples_t ( 0 to 3 );
    signal tdc_a : a_samples_t ( 0 to 1 );
    signal tdc_cnt : unsigned ( TDC_CNT_BITS-1 downto 0 );
    signal tdc_events : tdc_events_t;

    -- acquisition fifo buffer
    constant ACQ_BUFFER_CNT_BITS: natural := 16;
    component fifo_adc_core
    port (
        rst: in std_logic;
        wr_clk: in std_logic;
        rd_clk: in std_logic;
        din : IN std_logic_vector(31 downto 0);
        wr_en: in std_logic;
        rd_en: in std_logic;
        dout : out std_logic_vector(15 downto 0);
        full: out std_logic;
        empty: out std_logic;
        rd_data_count: out std_logic_vector(ACQ_BUFFER_CNT_BITS-1 downto 0)
    );
    end component;
    signal acq_buffer_din: std_logic_vector(31 downto 0);
    signal acq_buffer_dout: std_logic_vector(15 downto 0);
    signal acq_buffer_count: std_logic_vector(ACQ_BUFFER_CNT_BITS-1 downto 0);
    signal acq_buffer_rst: std_logic;
    signal acq_buffer_full: std_logic;
    signal acq_buffer_empty: std_logic;
    signal acq_buffer_rd: std_logic;
    signal acq_buffer_wr: std_logic;
    
    signal acq_buffer_din_valid : std_logic := '0';
    signal acq_data_select : std_logic_vector(1 downto 0) := (others => '0');
    signal acq_start_trig_mask : std_logic_vector(3 downto 0) := (others => '0');
    signal acq_stop_trig_en : std_logic_vector(1 downto 0) := (others => '0');
    signal acq_reset_soft : std_logic := '0';
    signal acq_stop_soft: std_logic := '0';
    signal acq_state_cdc, acq_state_toglobal : std_logic_vector(2 downto 0) := (others => '0');

    -- communication signals/registers
    signal comm_to_global, comm_to_ram, comm_to_adcprog, comm_to_acqbuf: comm_to_slave_t;
    signal comm_from_global, comm_from_ram, comm_from_adcprog, comm_from_acqbuf: comm_from_slave_t;
    
    -- global registers
    signal global_status: std_logic_vector(2 downto 0);
    signal global_conf, global_conf_cdc: std_logic_vector(15 downto 0) := (others => '0');
    signal acq_conf, acq_conf_cdc: std_logic_vector(15 downto 0) := (others => '0');

    constant VERSION: natural := 159;
begin

LED1 <= tdc_d(0)(0);
LED2 <= tdc_d(0)(1);

-- communication slave select
slave_select: process(comm_addr, comm_to_slave, comm_from_global, comm_from_adcprog, comm_from_acqbuf)
    constant not_selected: comm_to_slave_t := (rd_req => '0', wr_req => '0', data_wr => (others => '-'));
    constant invalid_slave: comm_from_slave_t := (rd_ack => '1', wr_ack => '1', data_rd => (others => '1'));
begin
    -- no read/write requests to unselected slaves
    comm_to_global <= not_selected;
    comm_to_ram <= not_selected;
    comm_to_adcprog <= not_selected;
    comm_to_acqbuf <= not_selected;
    -- don't stall when reading from invalid slave address, no error reporting
    comm_from_slave <= invalid_slave;
    -- select communication slave based on comm_addr
    case to_integer(comm_addr) is
        when 0 =>
            comm_to_global <= comm_to_slave;
            comm_from_slave <= comm_from_global;
        when 2 =>
            comm_to_ram <= comm_to_slave;
            comm_from_slave <= comm_from_ram;
        when 3 =>
            comm_to_adcprog <= comm_to_slave;
            comm_from_slave <= comm_from_adcprog;
        when 4 =>
            comm_to_acqbuf <= comm_to_slave;
            comm_from_slave <= comm_from_acqbuf;
        when others =>
            null;
    end case;
end process;

-- read global registers
process(comm_to_global, comm_port, global_status, global_conf)
begin
    comm_from_global <= (rd_ack => '1', wr_ack => '1', data_rd => (others => '0'));

    case to_integer(comm_port) is
        when 0 =>
            -- read global configuration register
            comm_from_global.data_rd(global_conf'range) <= global_conf;
        when 1 =>
            -- read global status register
            comm_from_global.data_rd(global_status'range) <= global_status;
        when 3 =>
            -- read version
            comm_from_global.data_rd <= std_logic_vector(to_unsigned(VERSION, 16));
        when 5 =>
            -- read acquisition configuration register
            comm_from_global.data_rd(acq_conf'range) <= acq_conf;
        when 6 =>
            -- read device temperature
            comm_from_global.data_rd(device_temp'range) <= device_temp;
        when others =>
            null;
    end case;
end process;

-- write global registers
global_registers: process(clk_main)
begin
    if rising_edge(clk_main) then
        -- update status registers
        global_status <= acq_state_cdc;  -- TODO: more to follow
        
        -- write register 0 (global_conf)
        if comm_to_global.wr_req = '1' and to_integer(comm_port) = 0 then
            global_conf <= comm_to_global.data_wr(global_conf'range);
        end if;
        -- write register 4 (threshold)
        if comm_to_global.wr_req = '1' and to_integer(comm_port) = 4 then
            tdc_a_threshold_cd1 <= signed(comm_to_global.data_wr(tdc_a_threshold_cd1'range));
        end if;
        -- write register 5 (acquisition conf)
        if comm_to_global.wr_req = '1' and to_integer(comm_port) = 5 then
            acq_conf <= comm_to_global.data_wr(acq_conf'range);
        end if;
    end if;
end process;
sync_global_conf: slow_cdc_bits
port map (
    clk => clk_samples,
    din => global_conf,
    dout => global_conf_cdc
);
sync_acq_conf: slow_cdc_bits
port map (
    clk => clk_samples,
    din => acq_conf,
    dout => acq_conf_cdc
);

-- global conf mapping
APWR_EN <= global_conf(1);
ADC_SRESETB <= not global_conf(2);
ADC_ENABLE <= global_conf(3);
sampling_rst <= global_conf_cdc(4);
tdc_a_average <= global_conf_cdc(14 downto 13);
tdc_a_invert <= global_conf_cdc(15);

-- acquisition conf mapping
acq_reset_soft <= acq_conf_cdc(0);
acq_stop_soft <= acq_conf_cdc(1);
acq_data_select <= acq_conf_cdc(3 downto 2);
acq_start_trig_mask <= acq_conf_cdc(7 downto 4);
acq_stop_trig_en <= acq_conf_cdc(9 downto 8);

-- ram comm slave
process(clk_main)
    constant RAM_CMD_WR: std_logic_vector(2 downto 0) := "000";
    constant RAM_CMD_RD: std_logic_vector(2 downto 0) := "001";
    variable n: integer;
    variable ram_rd_data_last: std_logic_vector(ram_rd_data'range) := (others => '0');
    variable ram_addr_reg: std_logic_vector(ram_addr'range) := (others => '0');
begin
    if rising_edge(clk_main) then
        -- default, no ram activity, no comm answer
        comm_from_ram <= (rd_ack => '0', wr_ack => '0', data_rd => (others => '-'));
        ram_en <= '0';
        ram_addr <= ram_addr_reg;
        ram_wdf_wren <= '0';
        ram_wdf_end <= '0';

        n := to_integer(comm_port);
        if (n < 8) then
            -- write to ram_wr buffer or read from last ram word
            if comm_to_ram.wr_req = '1' then
                -- write word to ram write buffer
                ram_wdf_data(((n+1)*16-1) downto (n*16)) <= comm_to_ram.data_wr;
                comm_from_ram.wr_ack <= '1';
            elsif comm_to_ram.rd_req = '1' then
                -- read word from ram read buffer
                comm_from_ram.data_rd <= ram_rd_data_last(((n+1)*16-1) downto (n*16));
                comm_from_ram.rd_ack <= '1';
            end if;
        elsif (n = 8) then
            if comm_to_ram.wr_req = '1' then
                -- write low address bits
                ram_addr_reg(15 downto 0) := comm_to_ram.data_wr;
                comm_from_ram.wr_ack <= '1';
            end if; 
        elsif (n = 9) then
            if comm_to_ram.wr_req = '1' then
                -- write high address bits
                ram_addr_reg(27 downto 16) := comm_to_ram.data_wr(11 downto 0);
                comm_from_ram.wr_ack <= '1';
            end if;
        else
            -- send read or write command to ram
            if comm_to_ram.wr_req = '1' then
                comm_from_ram.wr_ack <= '1';
                if comm_to_ram.data_wr(0) = '0' then
                    -- ram write command
                    ram_wdf_wren <= '1';
                    ram_wdf_end <= '1';
                    ram_cmd <= RAM_CMD_WR;
                    ram_en <= '1';
                else
                    -- ram read command
                    ram_cmd <= RAM_CMD_RD;
                    ram_en <= '1';
                end if;
            end if;
        end if;
        
        -- store last word from ram
        if (ram_rd_data_valid = '1') then
            ram_rd_data_last := ram_rd_data;
        end if;
    end if;
end process;

-- adc programming requests
adc_program_reg: process(clk_main)
    variable read_cmd: std_logic;
begin
    if rising_edge(clk_main) then
        adc_prog_start <= '0';

        -- write address for adc programming request
        -- start adc read operation if address read bit is set
        if to_integer(comm_port) = 0 and comm_to_adcprog.wr_req = '1' then
            adc_prog_addr <= comm_to_adcprog.data_wr(adc_prog_addr'range);
            read_cmd := comm_to_adcprog.data_wr(7);
            adc_prog_rd <= read_cmd;
            if read_cmd = '1' then
                adc_prog_start <= '1';
            end if;
        end if;

        -- write data for adc programming request
        -- start adc write operation
        if to_integer(comm_port) = 1 and comm_to_adcprog.wr_req = '1' then
            adc_prog_din <= comm_to_adcprog.data_wr(adc_prog_din'range);
            adc_prog_start <= '1';
        end if;
    end if;
end process;
comm_from_adcprog.wr_ack <= not adc_prog_busy;
comm_from_adcprog.rd_ack <= '1';
comm_from_adcprog.data_rd <= adc_prog_dout;


--------------------------------------------------------------------------------

sync_a_threshold: slow_cdc_bits
port map (
    clk => clk_samples,
    din => std_logic_vector(tdc_a_threshold_cd1),
    dout => tdc_a_threshold_cd2slv
);
tdc_a_threshold_cd2 <= signed(tdc_a_threshold_cd2slv);

tdc_sample_prep_inst: tdc_sample_prep
generic map (CNT_BITS => TDC_CNT_BITS)
port map(
    clk           => clk_samples,
    samples_d_in  => samples_d,
    samples_a_in  => samples_a,
    a_threshold   => tdc_a_threshold_cd2,
    a_invert      => tdc_a_invert,
    a_average     => tdc_a_average,
    samples_d_out => tdc_d,
    samples_a_out => tdc_a,
    cnt           => tdc_cnt,
    tdc_events    => tdc_events
);

acquisition_process: process(clk_samples)    
    type acq_state_t is (s_reset, s_wait_ready, s_waittrig, s_buffering, s_done);
    variable tdc_cnt_zero: unsigned(tdc_cnt'range) := (others => '0');
    variable acq_state: acq_state_t := s_reset;
    variable tdc_cnt_ovfl: std_logic := '0';
    variable start_trig: boolean := false;
    variable stop_trig: boolean := false;
begin
    if rising_edge(clk_samples) then
        -- write state to global register, converted to unsigned/slv
        acq_state_toglobal <= std_logic_vector(to_unsigned(acq_state_t'pos(acq_state), 3));

        -- reset acquisition fifo when in reset state
        if acq_state = s_reset then
            acq_buffer_rst <= '1';
        else
            acq_buffer_rst <= '0';
        end if;

        -- counter overflow event
        if tdc_cnt = tdc_cnt_zero then
            tdc_cnt_ovfl := '1';
        else
            tdc_cnt_ovfl := '0';
        end if;

        -- start trigger (non masked events)
        start_trig := false;
        if tdc_cnt_ovfl = '1' and acq_start_trig_mask(3) = '0' then
            start_trig := true;
        end if;
        if tdc_events.d1_rising.valid = '1' and acq_start_trig_mask(2) = '0' then
            start_trig := true;
        end if;
        if tdc_events.d2_rising.valid = '1' and acq_start_trig_mask(1) = '0' then
            start_trig := true;
        end if;
        if tdc_events.a_maxfound.valid = '1' and acq_start_trig_mask(0) = '0' then
            start_trig := true;
        end if;

        -- stop trigger (enabled events)
        stop_trig := false;
        if acq_stop_soft = '1' then
            stop_trig := true;
        end if;
        if tdc_events.d1_rising.valid = '1' and acq_stop_trig_en(1) = '1' then
            stop_trig := true;
        end if;
        if tdc_events.d2_rising.valid = '1' and acq_stop_trig_en(0) = '1' then
            stop_trig := true;
        end if;

        -- state machine
        if acq_reset_soft = '1' then
            -- always go to reset state when acq_reset is high
            acq_state := s_reset;
        else
            -- state transitions
            case acq_state is
                when s_reset =>
                    acq_state := s_wait_ready;
                when s_wait_ready =>
                    if acq_buffer_full = '0' then
                        acq_state := s_waittrig;
                    end if;
                when s_waittrig =>
                    if start_trig then
                        acq_state := s_buffering;
                    end if;
                when s_buffering =>
                    if acq_buffer_full = '1' or stop_trig then
                        acq_state := s_done;
                    end if;
                when others =>
                    null;
                end case;
        end if;
        
        -- select signals for fifo input
        case acq_data_select is
        when "00" =>
            -- raw sample mode (digital + analog)
            acq_buffer_din <= tdc_d(0)(0) & tdc_d(1)(0) & tdc_d(2)(0) & tdc_d(3)(0) & std_logic_vector(tdc_a(0)) &
                              tdc_d(0)(1) & tdc_d(1)(1) & tdc_d(2)(1) & tdc_d(3)(1) & std_logic_vector(tdc_a(1));
            acq_buffer_din_valid <= '1';
        when "01" =>
            -- maxfind debug mode (analog + single digital + maxfind)
            acq_buffer_din <= tdc_d(0)(0) & tdc_d(1)(0) & tdc_d(2)(0) & tdc_d(3)(0) & std_logic_vector(tdc_a(0)) &
                              '0' & to_std_logic_vector(tdc_events.a_maxfound) & std_logic_vector(tdc_a(1));
            acq_buffer_din_valid <= '1';
        when "10" =>
            -- TDC mode (counter + events)
            acq_buffer_din <= tdc_cnt_ovfl &                           -- overflow(31)
                              to_std_logic_vector(tdc_events.a_maxfound) & -- valid(30) + pos(29-28)
                              to_std_logic_vector(tdc_events.d1_rising) &  -- valid(27) + pos(26-25)
                              to_std_logic_vector(tdc_events.d2_rising) &  -- valid(24) + pos(23-22)
                              std_logic_vector(tdc_cnt);                -- cnt(21-0)
            acq_buffer_din_valid <= tdc_cnt_ovfl or tdc_events.d1_rising.valid or tdc_events.d2_rising.valid or tdc_events.a_maxfound.valid;
        when others =>
            -- TDC + height mode (counter + maxvalue)
            acq_buffer_din <= (others => '0');
            if tdc_events.a_maxfound.valid = '1' then
                -- use only the last 10 bits from maxvalue (assume non-negative value -> unsigned 10bit)
                acq_buffer_din(31 downto 22) <= std_logic_vector(tdc_events.a_maxvalue(9 downto 0));
            end if;
            acq_buffer_din(21 downto 0) <= std_logic_vector(tdc_cnt);
            acq_buffer_din_valid <= tdc_cnt_ovfl or tdc_events.a_maxfound.valid;
        end case;
        
        -- override data valid if not in buffering state
        if acq_state /= s_buffering then
            acq_buffer_din_valid <= '0';
        end if;
    end if;
end process;
acq_buffer_wr <= acq_buffer_din_valid;

sync_acq_state: slow_cdc_bits
port map (
    clk => clk_main,
    din => acq_state_toglobal,
    dout => acq_state_cdc
);

fifo_acq_inst: fifo_adc_core
port map (
    rst => acq_buffer_rst,
    wr_clk => clk_samples,
    rd_clk => clk_main,
    din => acq_buffer_din,
    wr_en => acq_buffer_wr,
    rd_en => acq_buffer_rd,
    dout => acq_buffer_dout,
    full => acq_buffer_full,
    empty => acq_buffer_empty,
    rd_data_count => acq_buffer_count
);

-- read acquisition buffer
adc_buffer_read: process(comm_port, comm_to_acqbuf, acq_buffer_empty, acq_buffer_dout, acq_buffer_count)
begin
    comm_from_acqbuf <= (rd_ack => '1', wr_ack => '1', data_rd => (others => '0'));
    acq_buffer_rd <= '0';
    case to_integer(comm_port) is
    when 0 =>
        -- read fifo size
        comm_from_acqbuf.data_rd(acq_buffer_count'range) <= acq_buffer_count;
    when 1 =>
        -- read fifo data word
        acq_buffer_rd <= comm_to_acqbuf.rd_req;
        comm_from_acqbuf.rd_ack <= not acq_buffer_empty;
        comm_from_acqbuf.data_rd(acq_buffer_dout'range) <= acq_buffer_dout;
    when others =>
        null;
    end case;
end process;

end application_arch;