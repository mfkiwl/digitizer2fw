-------------------------------------------------------------------------------
-- Application logic
--
-- Author: Peter Würtz, TU Kaiserslautern (2016)
-- Distributed under the terms of the GNU General Public License Version 3.
-- The full license is in the file COPYING.txt, distributed with this software.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.communication_pkg.all;
use work.sampling_pkg.all;
use work.tdc_sample_prep_pkg.all;

library unisim;
use unisim.vcomponents.all;

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

    component acquisition is
    generic ( TDC_CNT_BITS: natural := 22 );
    port (
        -- acquisition domain
        clk_samples: in std_logic;
        samples_d_in: in din_samples_t(0 to 3);
        samples_a_in: in adc_samples_t(0 to 1);
        a_threshold: in a_sample_t;
        a_invert: in std_logic;
        a_average: in std_logic_vector(1 downto 0);
        acq_mode: in std_logic_vector(1 downto 0);
        acq_start_src: in std_logic_vector(2 downto 0);
        acq_stop_src: in std_logic_vector(2 downto 0);
        acq_reset: in std_logic;
        acq_stop: in std_logic;
        acq_state: out std_logic_vector(2 downto 0);
        -- application domain
        clk_rd: in std_logic;
        rd_en: in std_logic;
        rd_empty: out std_logic;
        rd_data: out std_logic_vector(15 downto 0);
        rd_2xcnt: out std_logic_vector(15 downto 0)
    );
    end component;

    signal acq_buffer_dout: std_logic_vector(15 downto 0);
    signal acq_buffer_2xcnt: std_logic_vector(15 downto 0);
    signal acq_buffer_empty: std_logic;
    signal acq_buffer_rd: std_logic;
    
    signal a_threshold_in_main, a_threshold_in_acq : std_logic_vector(11 downto 0);
    signal a_invert      : std_logic;
    signal a_average     : std_logic_vector(1 downto 0);
    signal acq_mode      : std_logic_vector(1 downto 0) := (others => '0');
    signal acq_start_src : std_logic_vector(2 downto 0) := (others => '0');
    signal acq_stop_src  : std_logic_vector(2 downto 0) := (others => '0');
    signal acq_reset     : std_logic := '0';
    signal acq_stop      : std_logic := '0';
    signal acq_state_in_acq, acq_state_in_main : std_logic_vector(2 downto 0) := (others => '0');

    -- communication signals/registers
    signal comm_to_global, comm_to_ram, comm_to_adcprog, comm_to_acqbuf: comm_to_slave_t;
    signal comm_from_global, comm_from_ram, comm_from_adcprog, comm_from_acqbuf: comm_from_slave_t;
    
    -- global registers
    signal usr_access_data: std_logic_vector(31 downto 0);
    signal global_status: std_logic_vector(2 downto 0);
    signal global_conf, global_conf_in_acq: std_logic_vector(15 downto 0) := (others => '0');
    signal acq_conf_in_main, acq_conf_in_acq: std_logic_vector(15 downto 0) := (others => '0');
begin

LED1 <= '0';
LED2 <= '0';

-- read user logic version
USR_ACCESSE2_inst : USR_ACCESSE2
port map (
    CFGCLK => open,
    DATA => usr_access_data,
    DATAVALID => open
);

-- communication slave select
slave_select: process(comm_addr, comm_to_slave, comm_from_global, comm_from_ram, comm_from_adcprog, comm_from_acqbuf)
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
process(comm_port, global_conf, global_status, acq_conf_in_main, device_temp)
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
            -- read version (upper)
            comm_from_global.data_rd <= usr_access_data(31 downto 16);
        when 4 =>
            -- read version (lower)
            comm_from_global.data_rd <= usr_access_data(15 downto 0);
        when 5 =>
            -- read acquisition configuration register
            comm_from_global.data_rd(acq_conf_in_main'range) <= acq_conf_in_main;
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
        global_status <= acq_state_in_main;  -- TODO: more to follow
        
        -- write register 0 (global_conf)
        if comm_to_global.wr_req = '1' and to_integer(comm_port) = 0 then
            global_conf <= comm_to_global.data_wr(global_conf'range);
        end if;
        -- write register 4 (threshold)
        if comm_to_global.wr_req = '1' and to_integer(comm_port) = 4 then
            a_threshold_in_main <= comm_to_global.data_wr(a_threshold_in_main'range);
        end if;
        -- write register 5 (acquisition conf)
        if comm_to_global.wr_req = '1' and to_integer(comm_port) = 5 then
            acq_conf_in_main <= comm_to_global.data_wr(acq_conf_in_main'range);
        end if;
    end if;
end process;

-- application-acquisition domain crossing
sync_global_conf: slow_cdc_bits
port map (
    clk => clk_samples,
    din => global_conf,
    dout => global_conf_in_acq
);
sync_acq_conf: slow_cdc_bits
port map (
    clk => clk_samples,
    din => acq_conf_in_main,
    dout => acq_conf_in_acq
);
sync_a_threshold: slow_cdc_bits
port map (
    clk => clk_samples,
    din => a_threshold_in_main,
    dout => a_threshold_in_acq
);

sync_acq_state: slow_cdc_bits
port map (
    clk => clk_main,
    din => acq_state_in_acq,
    dout => acq_state_in_main
);

-- global conf mapping
APWR_EN      <= global_conf(1);
ADC_SRESETB  <= not global_conf(2);
ADC_ENABLE   <= global_conf(3);
sampling_rst <= global_conf_in_acq(4);
a_average    <= global_conf_in_acq(14 downto 13);
a_invert     <= global_conf_in_acq(15);

-- acquisition conf mapping
acq_reset     <= acq_conf_in_acq(0);
acq_stop      <= acq_conf_in_acq(1);
acq_mode      <= acq_conf_in_acq(3 downto 2);
acq_start_src <= acq_conf_in_acq(6 downto 4);
acq_stop_src  <= acq_conf_in_acq(9 downto 7);

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

-- read acquisition buffer
adc_buffer_read: process(comm_port, comm_to_acqbuf, acq_buffer_empty, acq_buffer_dout, acq_buffer_2xcnt)
begin
    comm_from_acqbuf <= (rd_ack => '1', wr_ack => '1', data_rd => (others => '0'));
    acq_buffer_rd <= '0';
    case to_integer(comm_port) is
    when 0 =>
        -- read fifo size
        comm_from_acqbuf.data_rd(acq_buffer_2xcnt'range) <= acq_buffer_2xcnt;
    when 1 =>
        -- read fifo data word
        acq_buffer_rd <= comm_to_acqbuf.rd_req;
        comm_from_acqbuf.rd_ack <= not acq_buffer_empty;
        comm_from_acqbuf.data_rd(acq_buffer_dout'range) <= acq_buffer_dout;
    when others =>
        null;
    end case;
end process;

acquisition_inst: acquisition
port map(
    -- acquisition domain
    clk_samples   => clk_samples,
    samples_d_in  => samples_d,
    samples_a_in  => samples_a,
    a_threshold   => signed(a_threshold_in_acq),
    a_invert      => a_invert,
    a_average     => a_average,
    acq_mode      => acq_mode,
    acq_start_src => acq_start_src,
    acq_stop_src  => acq_stop_src,
    acq_reset     => acq_reset,
    acq_stop      => acq_stop,
    acq_state     => acq_state_in_acq,
    -- application domain
    clk_rd   => clk_main,
    rd_en    => acq_buffer_rd,
    rd_empty => acq_buffer_empty,
    rd_data  => acq_buffer_dout,
    rd_2xcnt => acq_buffer_2xcnt
);

end application_arch;