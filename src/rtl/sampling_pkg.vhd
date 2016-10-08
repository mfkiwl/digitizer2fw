library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package sampling_pkg is

    constant ADC_SAMPLE_BITS: integer := 12;

    type adc_sample_t is
        record
            data: std_logic_vector(ADC_SAMPLE_BITS-1 downto 0);
            ovfl: std_logic;
        end record;
    function to_std_logic_vector(x: adc_sample_t) return std_logic_vector;
    function to_adc_sample_t(x: std_logic_vector) return adc_sample_t;
    type adc_samples_t is array (natural range <>) of adc_sample_t;
    type din_samples_t is array (natural range <>) of std_logic_vector(1 downto 0);

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
        samples_d: out din_samples_t(0 to 3);
        samples_a: out adc_samples_t(0 to 1);
        -- control
        rst: in std_logic
    );
    end component;

end sampling_pkg;

package body sampling_pkg is

function to_std_logic_vector(x: adc_sample_t) return std_logic_vector is
    variable result: std_logic_vector(ADC_SAMPLE_BITS downto 0);
begin
    result(ADC_SAMPLE_BITS) := x.ovfl;
    result(ADC_SAMPLE_BITS-1 downto 0) := std_logic_vector(x.data);
    return result;
end to_std_logic_vector;

function to_adc_sample_t(x: std_logic_vector) return adc_sample_t is
    variable result: adc_sample_t;
begin
    result.ovfl := x(x'low + ADC_SAMPLE_BITS);
    result.data := std_logic_vector(x(x'low + ADC_SAMPLE_BITS-1 downto x'low));
    return result;
end to_adc_sample_t;

end sampling_pkg;
