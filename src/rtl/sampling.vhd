-------------------------------------------------------------------------------
-- Sampling module
--
-- This component captures the data from the analog and digital inputs.
-- The data samples are forwarded to the application using the ADC data clock
-- frequency of 250 MHz (2 analog samples per cycle). From this clock a digital
-- sampling clock is synthesized at 1 GHz (4 digital samples per cycle).
--
-- The temporal order of the sample outputs is from left to right.
-------------------------------------------------------------------------------

library unisim;
use unisim.vcomponents.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sampling_pkg.all;

entity sampling is
    port (
        -- data in from pins
        DIN_P: in std_logic_vector(1 downto 0);
        DIN_N: in std_logic_vector(1 downto 0);
        ADC_DA_P: in std_logic_vector(12 downto 0);
        ADC_DA_N: in std_logic_vector(12 downto 0);
        ADC_DACLK_P: in std_logic;
        ADC_DACLK_N: in std_logic;
        -- data in to device
        app_clk: out std_logic;
        samples_d: out din_samples_t(0 to 3);
        samples_a: out adc_samples_t(0 to 1);
        -- control
        rst: in std_logic
    );
end sampling;

architecture sampling_arch of sampling is

    constant SAMPLES_A_PER_CLK: natural := 2;
    constant SAMPLES_D_PER_CLK: natural := 4;

    constant sampling_enable: std_logic := '1';
    
    signal rst_int: std_logic_vector(2 downto 0) := (others => '0');
    attribute ASYNC_REG: string;
    attribute SHREG_EXTRACT: string;
    attribute ASYNC_REG of rst_int: signal is "true";
    attribute SHREG_EXTRACT of rst_int: signal is "no";

    component sampling_daclk_core
    port (
        adc_daclk_in: in std_logic;
        adc_daclk: out std_logic
    );
    end component;
    signal adc_daclk_in, clk_da: std_logic;

    constant ADC_DA_INV_MAP: std_logic_vector(ADC_DA_P'range) := "1111110000000";
    signal ADC_DA_int, ADC_DA_int_inv: std_logic_vector(ADC_DA_P'range);
    type adc_da_arr_t is array (natural range <>) of std_logic_vector(ADC_DA_P'range);
    signal adc_da_arr: adc_da_arr_t(0 to SAMPLES_A_PER_CLK-1);

    component sampling_din_core 
    port (
        clk_dsample_in: in std_logic;
        clk_dsample_fb: out std_logic;
        clk_dsample: out std_logic;
        clk_dsample_div: out std_logic
    );
    end component;
    signal clk_dsample_fb: std_logic;
    signal clk_dsample, clk_dsample_bufio, clk_dsample_bufio_inv: std_logic;
    signal clk_dsample_div, clk_dsample_div_bufr: std_logic;

    signal DIN_int, DIN_int_inv: std_logic_vector(DIN_P'range);
    type din_arr_t is array (natural range <>) of std_logic_vector(DIN_P'range);
    signal din_arr, din_arr_buf: din_arr_t(0 to SAMPLES_D_PER_CLK-1);
begin

-- register reset signal in sample clock domain
process(clk_da)
begin
    if rising_edge(clk_da) then
        rst_int <= rst_int(rst_int'high-1 downto 0) & rst;
    end if;
end process;

-------------------------------------------------------------------------------
-- analog capture
-------------------------------------------------------------------------------

-- generate 0-phase clk_da from input ADC_DACLK (remove clock input delay)
ADC_DACLK_IBUFDS: IBUFDS
port map (
    I => ADC_DACLK_P,
    IB => ADC_DACLK_N,
    O => adc_daclk_in
);
sampling_daclk_core_inst: sampling_daclk_core
port map (
    adc_daclk_in => adc_daclk_in,
    adc_daclk => clk_da
);
app_clk <= clk_da;

-- capture ADC_DA signals to adc_da_arr
GEN_ADC_IN: for I in ADC_DA_P'low to ADC_DA_P'high generate
    -- for each DA signal, generate IBUFDS and IDDR
    -- flip bits from inverted LVDS pairs (ADC_DA_INV_MAP)
    IBUFDS_inst: IBUFDS
    port map (
        I => ADC_DA_P(I),
        IB => ADC_DA_N(I),
        O => ADC_DA_int(I)
    );
    ADC_DA_int_inv(I) <= not ADC_DA_int(I);

    NORMAL: if ADC_DA_INV_MAP(I) = '0' generate
        IDDR_inst: IDDR 
        generic map (DDR_CLK_EDGE => "OPPOSITE_EDGE") 
        port map (
            Q1 => adc_da_arr(0)(I),
            Q2 => adc_da_arr(1)(I),
            C => clk_da, CE => sampling_enable,
            D => ADC_DA_int(I),
            R => '0', S => '0'
        );
    end generate NORMAL;
    INVERTED: if ADC_DA_INV_MAP(I) = '1' generate
        IDDR_inst: IDDR 
        generic map (DDR_CLK_EDGE => "OPPOSITE_EDGE") 
        port map (
            Q1 => adc_da_arr(0)(I),
            Q2 => adc_da_arr(1)(I),
            C => clk_da, CE => sampling_enable,
            D => ADC_DA_int_inv(I),
            R => '0', S => '0'
        );
    end generate INVERTED;
end generate GEN_ADC_IN;

-- typecast and register analog output
process(clk_da)
begin
    if rising_edge(clk_da) then
        for I in 0 to SAMPLES_A_PER_CLK-1 loop
            samples_a(I) <= to_adc_sample_t(adc_da_arr(I));
        end loop;
    end if;
end process;

-------------------------------------------------------------------------------
-- digital capture
-------------------------------------------------------------------------------

-- generate digital capture clocks from analog clock (fixed phase)
sampling_din_core_inst: sampling_din_core
port map (
    clk_dsample_in => adc_daclk_in,
    clk_dsample_fb => clk_dsample_fb,
    clk_dsample => clk_dsample,
    clk_dsample_div => clk_dsample_div
);

-- route digital capture clocks through BUFIO/BUFR
CLK_DSAMPLE_BUFIO_INST: BUFIO
port map (I => clk_dsample, O => clk_dsample_bufio);
clk_dsample_bufio_inv <= not clk_dsample_bufio;

CLK_DSAMPLE_DIV_BUFR_INST: BUFR
generic map (BUFR_DIVIDE => "1", SIM_DEVICE => "7SERIES")
port map (I => clk_dsample_div, CE => '1', CLR => '0', O => clk_dsample_div_bufr);

-- capture DIN signals to din_arr
GEN_DIG_IN: for I in DIN_P'low to DIN_P'high generate
    -- for each DIN signal, generate IBUFDS and ISERDESE2
    -- account for inverted LVDS pairs
    IBUFDS_inst: IBUFDS
    port map (
        I => DIN_P(I),
        IB => DIN_N(I),
        O => DIN_int(I)
    );
    DIN_int_inv(I) <= not DIN_int(I);
    ISERDESE2_inst: ISERDESE2
    generic map (
        DATA_RATE => "DDR", DATA_WIDTH => 4, INTERFACE_TYPE => "NETWORKING",
        IOBDELAY => "NONE", NUM_CE => 2, OFB_USED => "FALSE", SERDES_MODE => "MASTER"
    )
    port map (
        -- Q1 - Q8: 1-bit (each) output: Registered data outputs
        Q1 => din_arr(3)(I), -- newest
        Q2 => din_arr(2)(I),
        Q3 => din_arr(1)(I),
        Q4 => din_arr(0)(I), -- oldest
        Q5 => open, Q6 => open, Q7 => open, Q8 => open,
        -- Clocks: 1-bit (each) input: ISERDESE2 clock input ports
        CLK => clk_dsample_bufio,
        CLKB => clk_dsample_bufio_inv,
        CLKDIV => clk_dsample_div_bufr,
        CLKDIVP => '0', 
        -- Input Data: 1-bit (each) input: ISERDESE2 data input ports
        D => DIN_int_inv(I),
        DDLY => '0',
        -- control
        CE1 => sampling_enable, CE2 => sampling_enable,
        RST => rst_int(rst_int'high),
        BITSLIP => '0',
        -- unused
        DYNCLKDIVSEL => '0', DYNCLKSEL => '0',
        SHIFTIN1 => '0', SHIFTIN2 => '0',
        SHIFTOUT1 => open, SHIFTOUT2 => open,
        O => open, OFB => '0',
        OCLK => '0', OCLKB => '0'
    );
end generate GEN_DIG_IN;

-- recapture din_arr in clk_div domain
process (clk_dsample_div_bufr)
begin
    if rising_edge(clk_dsample_div_bufr) then
        din_arr_buf <= din_arr;
    end if;
end process;

-- register digital output in analog clock domain
process(clk_da)
begin
    if rising_edge(clk_da) then
        for I in 0 to SAMPLES_D_PER_CLK-1 loop
            samples_d(I) <= din_arr_buf(I);
        end loop;
    end if;
end process;

end sampling_arch;
