library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

entity sampling_tb is
end sampling_tb;

architecture sampling_tb_arch of sampling_tb is

    component sampling
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
        samples_d: out std_logic_vector(7 downto 0);
        samples_a: out std_logic_vector(25 downto 0);
        -- control
        rst: in std_logic
    );
    end component;
    signal clk_samples: std_logic := '0';
    signal samples_d: std_logic_vector(7 downto 0 ) := (others => '0');
    signal samples_a: std_logic_vector(25 downto 0 ) := (others => '0');
    signal sampling_rst: std_logic := '0';

    signal DIN_P: std_logic_vector(1 downto 0) := (others => '1');
    signal DIN_N: std_logic_vector(1 downto 0) := (others => '0');
    signal ADC_DA_P: std_logic_vector(12 downto 0) := (others => '0');
    signal ADC_DA_N: std_logic_vector(12 downto 0) := (others => '1');
    signal ADC_DACLK_P: std_logic := '0';
    signal ADC_DACLK_N: std_logic := '0';
    
    constant daclk_period : time := 4 ns;
    
    signal app_clk: std_logic;

begin

sampling_inst: sampling
port map (
    DIN_P => DIN_P,
    DIN_N => DIN_N,
    ADC_DA_P => ADC_DA_P,
    ADC_DA_N => ADC_DA_N,
    ADC_DACLK_P => ADC_DACLK_P,
    ADC_DACLK_N => ADC_DACLK_N,
    app_clk => app_clk,
    samples_d => samples_d,
    samples_a => samples_a,
    rst => sampling_rst
);

clk_process: process
begin
    ADC_DACLK_P <= '0';
    ADC_DACLK_N <= '1';
    wait for daclk_period/2;
    ADC_DACLK_P <= '1';
    ADC_DACLK_N <= '0';
    wait for daclk_period/2;
end process;

stimulus: process
begin
    sampling_rst <= '1';
    for I in 0 to 20 loop
		wait until rising_edge(app_clk);
	end loop;
	sampling_rst <= '0';
	
	wait for 32 ns;
	DIN_P(0) <= '0';
	DIN_N(0) <= '1';
	wait;
end process;

end sampling_tb_arch;
