library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sampling_pkg.all;

package tdc_sample_prep_pkg is

    constant TDC_EVENT_POS_BITS: natural := 2;

    type tdc_event_t is
    record
        valid: std_logic;
        pos: unsigned(1 downto 0);
    end record;
    
    function to_std_logic_vector(x: tdc_event_t) return std_logic_vector;
    function to_tdc_event_t(x: std_logic_vector) return tdc_event_t;
    -- convert vector to a single event encoded as valid flag + position. extract first event only.
    function flat_events_to_event_t(flat: std_logic_vector(3 downto 0)) return tdc_event_t;

    type tdc_events_t is
    record
        d1_rising:  tdc_event_t;
        d1_falling: tdc_event_t;
        d2_rising:  tdc_event_t;
        d2_falling: tdc_event_t;
        a_maxfound: tdc_event_t;
        a_maxvalue: a_sample_t;
    end record;
    
    component tdc_sample_prep is
    generic (
        CNT_BITS: natural := 16
    );
    port (
        clk: in std_logic;
        samples_d_in: in din_samples_t(0 to 3);
        samples_a_in: in adc_samples_t(0 to 1);
        a_threshold: in a_sample_t;
        a_invert: in std_logic;
        a_average: in std_logic_vector(1 downto 0);
        --
        samples_d_out: out din_samples_t(0 to 3);
        samples_a_out: out a_samples_t(0 to 1);
        cnt: out unsigned(CNT_BITS-1 downto 0);
        tdc_events: out tdc_events_t
    );
    end component;

end tdc_sample_prep_pkg;

package body tdc_sample_prep_pkg is

function to_std_logic_vector(x: tdc_event_t) return std_logic_vector is
    variable result: std_logic_vector(1+TDC_EVENT_POS_BITS-1 downto 0);
begin
    result(TDC_EVENT_POS_BITS) := x.valid;
    result(TDC_EVENT_POS_BITS-1 downto 0) := std_logic_vector(x.pos);
    return result;
end to_std_logic_vector;

function to_tdc_event_t(x: std_logic_vector) return tdc_event_t is
    variable result: tdc_event_t;
begin
    result.valid := x(x'low + TDC_EVENT_POS_BITS);
    result.pos := unsigned(x(x'low + TDC_EVENT_POS_BITS-1 downto x'low));
    return result;
end to_tdc_event_t;

function flat_events_to_event_t(flat: std_logic_vector(3 downto 0)) return tdc_event_t is
    variable result: tdc_event_t := (valid => '0', pos => (others => '-'));
begin
    for I in 0 to 3 loop
        if flat(I) = '1' then
            result.valid := '1';
            result.pos := to_unsigned(3-I, 2);
        end if;
    end loop;
    return result;
end flat_events_to_event_t;

end tdc_sample_prep_pkg;
