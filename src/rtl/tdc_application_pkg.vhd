library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package tdc_application_pkg is

    type tdc_events_t is
        record
            cnt_ov: std_logic;
            d1_risings: std_logic_vector(3 downto 0);
            d2_risings: std_logic_vector(3 downto 0);
            a_maximum: std_logic_vector(1 downto 0);
        end record;
    function tdc_event(x: adc_sample_t) return std_logic_vector;
    function to_adc_sample_t(x: std_logic_vector) return adc_sample_t;

end tdc_application_pkg;

package body tdc_application_pkg is

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

end tdc_application_pkg;
