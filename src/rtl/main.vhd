library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use ieee.numeric_std.all;

library unisim;
use unisim.vcomponents.all;

use work.communication_pkg.all;
use work.sampling_pkg.all;

entity top_level is
port ( 
    LED1: out std_logic;
    LED2: out std_logic;
    -- GCLK1 : in std_logic;
    -- GPIO1_P : out std_logic;
    -- GPIO1_N : out std_logic;
    GND: out std_logic_vector(21 downto 0);

    -- USB
    USB_D: inout std_logic_vector(7 downto 0);
    USB_WR: out std_logic;
    USB_TXE: in std_logic;
    USB_RXF: in std_logic;
    USB_RD: out std_logic;
    USB_OE: out std_logic;
    USB_CLKOUT: in std_logic;
    USB_SIWUA: out std_logic;

    -- DRAM
    ddr3_dq: inout std_logic_vector(15 downto 0);
    ddr3_addr: out std_logic_vector(13 downto 0);
    ddr3_ba: out std_logic_vector(2 downto 0);
    ddr3_we_n: out std_logic;
    ddr3_reset_n: out std_logic;
    ddr3_ras_n: out std_logic;
    ddr3_cas_n: out std_logic;
    ddr3_odt: out std_logic_vector(0 downto 0);
    ddr3_cke: out std_logic_vector(0 downto 0);
    ddr3_ck_p: out std_logic_vector(0 downto 0);
    ddr3_ck_n: out std_logic_vector(0 downto 0);
    ddr3_dqs_p: inout std_logic_vector(1 downto 0);
    ddr3_dqs_n: inout std_logic_vector(1 downto 0);

    -- ADC
    APWR_EN: out std_logic;
    ADC_ENABLE: out std_logic;
    ADC_SRESETB: out std_logic;
    ADC_SDIO: inout std_logic;
    ADC_SDENB: out std_logic;
    ADC_SCLK: out std_logic;
    ADC_DA_P: in std_logic_vector(12 downto 0);
    ADC_DA_N: in std_logic_vector(12 downto 0);
    ADC_DACLK_P: in std_logic;
    ADC_DACLK_N: in std_logic;
    
    -- DIN
    DIN_P: in std_logic_vector(1 downto 0);
    DIN_N: in std_logic_vector(1 downto 0)
);
end top_level;

architecture top_level_arch of top_level is

    ----------------------------------------------------------------------------

    component application
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
    end component;
    
    ----------------------------------------------------------------------------

    -- clock resourcces
    component clk_core_main
    port (
        clk_in: in std_logic;
        clk_main: out std_logic;
        clk_ddr3_sys: out std_logic;
        clk_ddr3_ref: out std_logic
    );
    end component;
    component clk_core_usb
    port (
        clk_in: in std_logic;
        clk_usb: out std_logic
    );
    end component;
    signal clk_main: std_logic;
    signal clk_main_out, clk_ddr3_sys, clk_ddr3_ref, clk_usb: std_logic;

    -- adc serial programming
    component adc_program
    port (
        -- application interface
        clk_main: in std_logic;
        start: in std_logic;
        rd: in std_logic;
        busy: out std_logic;
        addr: in std_logic_vector(6 downto 0);
        din: in std_logic_vector(15 downto 0);
        dout: out std_logic_vector(15 downto 0);
        -- adc interface
        adc_sdenb: out std_logic;
        adc_sdio: inout std_logic;
        adc_sclk: out std_logic
    );
    end component;
    signal adc_prog_start: std_logic;
    signal adc_prog_rd: std_logic := '0';
    signal adc_prog_busy: std_logic;
    signal adc_prog_addr: std_logic_vector(6 downto 0);
    signal adc_prog_din: std_logic_vector(15 downto 0);
    signal adc_prog_dout: std_logic_vector(15 downto 0);

    -- analog/digital sampling
    signal clk_samples: std_logic;
    signal samples_d: din_samples_t(0 to 3);
    signal samples_a: adc_samples_t(0 to 1);
    signal sampling_rst: std_logic;

    -- host communication
    component ft2232_communication
    port (
        clk: in std_logic;
        rst: in std_logic;
        error: out std_logic;
        -- application bus interface
        slave_addr: out unsigned(5 downto 0);
        slave_port: out unsigned(5 downto 0);
        comm_to_slave: out comm_to_slave_t;
        comm_from_slave: in comm_from_slave_t;
        -- ftdi interface
        usb_clk: in std_logic;
        usb_oe_n: out std_logic;
        usb_rd_n: out std_logic;
        usb_wr_n: out std_logic;
        usb_rxf_n: in std_logic;
        usb_txe_n: in std_logic;
        usb_d: inout std_logic_vector(7 downto 0)
    );
    end component;
    signal comm_addr: unsigned(5 downto 0);
    signal comm_port: unsigned(5 downto 0);
    signal comm_error: std_logic;
    signal comm_to_slave: comm_to_slave_t;
    signal comm_from_slave: comm_from_slave_t;
begin

GND <= (others => '0');
clk_main <= clk_main_out;

clk_core_main_inst: clk_core_main
port map (
    clk_in => USB_CLKOUT,
    clk_main => clk_main_out,
    clk_ddr3_sys => clk_ddr3_sys,
    clk_ddr3_ref => clk_ddr3_ref
);
clk_core_usb_inst: clk_core_usb
port map (
    clk_in => USB_CLKOUT,
    clk_usb => clk_usb
);

adc_program_inst: adc_program
port map (
    clk_main => clk_main,
    start => adc_prog_start,
    rd => adc_prog_rd,
    busy => adc_prog_busy,
    addr => adc_prog_addr,
    din => adc_prog_din,
    dout => adc_prog_dout,
    adc_sdenb => ADC_SDENB,
    adc_sdio => ADC_SDIO,
    adc_sclk => ADC_SCLK
);

sampling_inst: sampling
port map (
    DIN_P => DIN_P,
    DIN_N => DIN_N,
    ADC_DA_P => ADC_DA_P,
    ADC_DA_N => ADC_DA_N,
    ADC_DACLK_P => ADC_DACLK_P,
    ADC_DACLK_N => ADC_DACLK_N,
    app_clk => clk_samples,
    samples_d => samples_d,
    samples_a => samples_a,
    rst => sampling_rst
);

ft2232_communication_inst: ft2232_communication
port map (
    clk => clk_main,
    rst => '0',
    error => comm_error,
    -- application register interface
    slave_addr => comm_addr,
    slave_port => comm_port,
    comm_to_slave => comm_to_slave,
    comm_from_slave => comm_from_slave,
    -- ftdi interface
    usb_clk => clk_usb,
    usb_oe_n => USB_OE,
    usb_rd_n => USB_RD,
    usb_wr_n => USB_WR,
    usb_rxf_n => USB_RXF,
    usb_txe_n => USB_TXE,
    usb_d => USB_D
);
USB_SIWUA <= '1';  -- do not use SIWUA feature for now

application_inst: application
port map (
    clk_main => clk_main,
    clk_samples => clk_samples,
    LED1 => LED1,
    LED2 => LED2,

    -- usb communication
    comm_addr => comm_addr,
    comm_port => comm_port,
    comm_to_slave => comm_to_slave,
    comm_from_slave => comm_from_slave,
    comm_error => comm_error,

    -- analog pwr/enable/rst
    APWR_EN => APWR_EN,
    ADC_ENABLE => ADC_ENABLE,
    ADC_SRESETB => ADC_SRESETB,

    -- adc program
    adc_prog_start => adc_prog_start,
    adc_prog_rd => adc_prog_rd,
    adc_prog_busy => adc_prog_busy,
    adc_prog_addr => adc_prog_addr,
    adc_prog_din => adc_prog_din,
    adc_prog_dout => adc_prog_dout,

    -- analog/digital samples
    sampling_rst => sampling_rst,
    samples_d => samples_d,
    samples_a => samples_a
);

end top_level_arch;