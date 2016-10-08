library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

entity adc_program_tb is
end adc_program_tb;

architecture adc_program_tb_arch of adc_program_tb is

    signal ADC_SDENB, ADC_SDIO, ADC_SCLK: std_logic;

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
    signal adc_prog_start: std_logic := '0';
    signal adc_prog_rd: std_logic := '0';
    signal adc_prog_busy: std_logic;
    signal adc_prog_addr: std_logic_vector(6 downto 0) := (others => '-');
    signal adc_prog_din: std_logic_vector(15 downto 0) := (others => '-');
    signal adc_prog_dout: std_logic_vector(15 downto 0) := (others => '-');

    constant clk_period : time := 10 ns;
    signal clk: std_logic;

begin

adc_program_inst: adc_program
port map (
    clk_main => clk,
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

clk_process: process
begin
    clk <= '0';
    wait for clk_period/2;
    clk <= '1';
    wait for clk_period/2;
end process;

stimulus: process
    constant ADDRESS: std_logic_vector := "0100011";
    constant WORD: std_logic_vector := "1100000011111111";
begin
    ADC_SDIO <= 'Z';
    adc_prog_start <= '0';
    adc_prog_addr <= ADDRESS;
    adc_prog_din <= WORD;

    -- start read cycle
    wait for clk_period/2;
    wait for 10 * clk_period;
    adc_prog_rd <= '1';
    adc_prog_start <= '1';
    wait for clk_period;
    adc_prog_start <= '0';
    
    -- wait until adc_prog stops driving SDIO and drive test signal
    wait until ADC_SDIO = 'Z';
    ADC_SDIO <= '0';
    wait for 200 ns;
    ADC_SDIO <= '1';
    wait until adc_prog_busy = '0';
    ADC_SDIO <= 'Z';
    
    -- wait a bit
    wait for 100 * clk_period;
    
    -- start write cycle
    adc_prog_rd <= '0';
    adc_prog_start <= '1';
    wait for clk_period;
    adc_prog_start <= '0';

    -- wait for finished
    wait until adc_prog_busy = '0';
    assert false report "Stimulus finished" severity note;
    wait;
end process;

end adc_program_tb_arch;
