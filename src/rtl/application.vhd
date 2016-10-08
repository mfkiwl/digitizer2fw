library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sampling_pkg.all;
use work.communication_pkg.all;

entity application is
port (
    clk_main: in std_logic;
    clk_samples: in std_logic;
    LED1: out std_logic;
    LED2: out std_logic;

    -- usb communication
    comm_addr: in unsigned(5 downto 0);
    comm_port: in unsigned(5 downto 0);
    comm_to_slave: in comm_to_slave_t;
    comm_from_slave: out comm_from_slave_t;
    comm_error: in std_logic;

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

    -- acquisition fifo buffer
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
        rd_data_count: out std_logic_vector(11 downto 0)
    );
    end component;
    signal acq_buffer_din: std_logic_vector(31 downto 0);
    signal acq_buffer_dout: std_logic_vector(15 downto 0);
    signal acq_buffer_count: std_logic_vector(11 downto 0);
    signal acq_buffer_rst: std_logic;
    signal acq_buffer_full: std_logic;
    signal acq_buffer_empty: std_logic;
    signal acq_buffer_rd: std_logic;
    signal acq_buffer_wr: std_logic;
    
    -- communication signals/registers
    signal comm_to_global, comm_to_adcprog, comm_to_acqbuf: comm_to_slave_t;
    signal comm_from_global, comm_from_adcprog, comm_from_acqbuf: comm_from_slave_t;
    
    -- global registers
    signal global_status: std_logic_vector(2 downto 0);
    signal global_cmd: std_logic_vector(15 downto 0) := (others => '0');
    signal global_conf: std_logic_vector(15 downto 0) := (others => '0');

    constant VERSION: natural := 150;
begin

LED1 <= '0';
LED2 <= '0';

-- communication slave select
slave_select: process(comm_addr, comm_to_slave, comm_from_global, comm_from_adcprog, comm_from_acqbuf)
    constant not_selected: comm_to_slave_t := (rd_req => '0', wr_req => '0', data_wr => (others => '-'));
    constant invalid_slave: comm_from_slave_t := (rd_ack => '1', wr_ack => '1', data_rd => (others => '1'));
begin
    -- no read/write requests to unselected slaves
    comm_to_global <= not_selected;
    comm_to_adcprog <= not_selected;
    comm_to_acqbuf <= not_selected;
    -- don't stall when reading from invalid slave address, no error reporting
    comm_from_slave <= invalid_slave;
    -- select communication slave based on comm_addr
    case to_integer(comm_addr) is
        when 0 =>
            comm_to_global <= comm_to_slave;
            comm_from_slave <= comm_from_global;
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
            comm_from_global.data_rd(global_conf'range) <= global_conf;
        when 1 =>
            comm_from_global.data_rd(global_status'range) <= global_status;
        when 3 =>
            comm_from_global.data_rd <= std_logic_vector(to_unsigned(VERSION, 16));
        when others =>
            null;
    end case;
end process;

-- write global registers
global_registers: process(clk_main)
begin
    if rising_edge(clk_main) then
        -- update status registers
        global_status(2 downto 0) <= (others => '0');  -- dram status bits (reserved)
        
        -- register write from usb
        if comm_to_global.wr_req = '1' and to_integer(comm_port) = 0 then
            global_conf <= comm_to_global.data_wr(global_conf'range);
        end if;
    end if;
end process;
APWR_EN <= global_conf(1);
ADC_SRESETB <= not global_conf(2);
ADC_ENABLE <= global_conf(3);
sampling_rst <= global_conf(4);
acq_buffer_rst <= global_conf(6);

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

acq_buffer_din <=
    samples_d(3)(0) & samples_d(2)(0) & samples_d(1)(0) & samples_d(0)(0) & 
    samples_a(0).data &
    samples_d(3)(1) & samples_d(2)(1) & samples_d(1)(1) & samples_d(0)(1) &
    samples_a(1).data;

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
acq_buffer_wr <= '1';

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