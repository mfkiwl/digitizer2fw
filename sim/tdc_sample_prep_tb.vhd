library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

use work.sampling_pkg.all;

entity tdc_sample_prep_tb is
end tdc_sample_prep_tb;

architecture tdc_sample_prep_tb_arch of tdc_sample_prep_tb is

    constant CNT_BITS: natural := 8;
    component tdc_sample_prep
    generic (
        CNT_BITS : natural := CNT_BITS
    );
    port (
        clk : in std_logic;
        samples_d_in : in din_samples_t( 0 to 3 );
        samples_a_in : in adc_samples_t( 0 to 1 );
        a_threshold : in a_sample_t;
        a_invert: in std_logic;
        a_average: in std_logic_vector( 1 downto 0 );
        samples_d_out : out din_samples_t( 0 to 3 );
        samples_a_out : out a_samples_t( 0 to 1 );
        cnt : out unsigned( CNT_BITS - 1 downto 0 );
        d1_risings : out std_logic_vector( 3 downto 0 );
        d2_risings : out std_logic_vector( 3 downto 0 );
        a_maxfound : out std_logic_vector( 3 downto 0 );
        a_maxvalue : out a_sample_t;
        events : out std_logic_vector( 3 downto 0 )
    );
    end component;
    signal samples_d_in: din_samples_t( 0 to 3 ) := (others => (others => '0'));
    signal samples_a_in: adc_samples_t( 0 to 1 ) := (others => (ovfl => '0', data => (others => '0')));
    signal a_threshold: a_sample_t := (others => '0');
    signal a_invert: std_logic := '0';
    signal a_average: std_logic_vector( 1 downto 0 ) := (others => '0');
    signal samples_d_out: din_samples_t( 0 to 3 );
    signal samples_a_out: a_samples_t( 0 to 1 );
    signal sample_cnt: unsigned(CNT_BITS-1 downto 0);
    signal d1_risings, d2_risings: std_logic_vector( 3 downto 0 );
    signal a_maxfound: std_logic_vector( 3 downto 0 );
    signal a_maxvalue: a_sample_t;
    signal events: std_logic_vector( 3 downto 0 );
    
    constant clk_period : time := 4 ns;
    signal clk: std_logic := '0';

begin

uut: tdc_sample_prep
port map(
    clk           => clk,
    samples_d_in  => samples_d_in,
    samples_a_in  => samples_a_in,
    a_threshold   => a_threshold,
    a_invert      => a_invert,
    a_average     => a_average,
    samples_d_out => samples_d_out,
    samples_a_out => samples_a_out,
    cnt           => sample_cnt,
    d1_risings    => d1_risings,
    d2_risings    => d2_risings,
    a_maxfound    => a_maxfound,
    a_maxvalue    => a_maxvalue,
    events        => events
);

clk_process: process
begin
    clk <= '0';
    wait for clk_period/2;
    clk <= '1';
    wait for clk_period/2;
end process;

stimulus: process
begin
    a_invert <= '1';
	wait for 10*clk_period;
	samples_d_in <= (others => (others => '1'));
	wait for 10*clk_period;
	samples_a_in(0).data <= to_signed(-1000, ADC_SAMPLE_BITS);
	samples_a_in(1).data <= to_signed(0, ADC_SAMPLE_BITS);
	wait for clk_period;
	samples_a_in <= (others => (ovfl => '0', data => (others => '0')));
    
	wait;
end process;

end tdc_sample_prep_tb_arch;
