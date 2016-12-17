-------------------------------------------------------------------------------
-- TDC sample preparation
--
-- This component processes the input signals looking for events, rising edges
-- for digital, maxfind for analog. The module also includes a sample counter
-- which also generates an event on overflow.
-------------------------------------------------------------------------------

library unisim;
use unisim.vcomponents.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sampling_pkg.all;
use work.maxfinder_pkg.all;
use work.tdc_sample_prep_pkg.all;

entity tdc_sample_prep is
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
end tdc_sample_prep;

architecture tdc_sample_prep_arch of tdc_sample_prep is
    -- input filtering
    signal samples_a_in_avg, samples_a_in_filt: adc_samples_t(0 to 1);

    -- queue samples for sample out alignment after rising/maximum detection
    constant D_QUEUE_LEN: natural := 2;
    constant A_QUEUE_LEN: natural := 8; -- 8
    type samples_d_buf_t is array(0 to D_QUEUE_LEN-1) of din_samples_t(0 to 3);
    type samples_a_buf_t is array(0 to A_QUEUE_LEN-1) of a_samples_t(0 to 1);
    signal samples_d_buf: samples_d_buf_t := (others => (others => (others => '0')));
    signal samples_a_buf: samples_a_buf_t := (others => (others => (others => '0')));

    -- sample counter
    signal sample_cnt_int: unsigned(CNT_BITS-1 downto 0) := (others => '0');

    -- digital processing
    component digital_edge_detect
    port (
        clk: in std_logic;
        samples_d: in din_samples_t(0 to 3);
        rising_d: out din_samples_t(0 to 3);
        falling_d: out din_samples_t(0 to 3)
    );
    end component;
    signal rising_d, falling_d: din_samples_t(0 to 3);
    signal d1_rising_int, d1_falling_int: std_logic_vector(3 downto 0) := (others => '0');
    signal d2_rising_int, d2_falling_int: std_logic_vector(3 downto 0) := (others => '0');
    
    -- analog processing
    component maxfinder_simple
    generic (
        N_FRAC_BITS: natural := 1;
        N_ADIFF_CLIP: natural := 0
    );
    port (
        clk: in std_logic;
        samples_in: in a_samples_t(0 to 1);
        threshold: in a_sample_t;
        max_found: out std_logic;
        max_pos: out unsigned(1+N_FRAC_BITS-1 downto 0);
        max_height: out a_sample_t
    );
    end component;
    signal max_samples_in: a_samples_t(0 to 1);
    signal max_found: std_logic;
    signal max_pos: unsigned(1 downto 0) := (others => '0');
    signal max_height: a_sample_t := (others => '0');
    signal a_maxfound_int: tdc_event_t;

begin

-- input filter
a_filter: entity work.sample_average
port map (
    clk => clk,
    n => a_average,
    samples_a_in => samples_a_in,
    samples_a_out => samples_a_in_avg
);
process(clk)
begin
    if rising_edge(clk) then
        for I in samples_a_in_avg'low to samples_a_in_avg'high loop
            samples_a_in_filt(I) <= samples_a_in_avg(I);
            if a_invert = '1' then
                samples_a_in_filt(I).data <= -samples_a_in_avg(I).data;
            end if;
        end loop;
    end if;
end process;

-- sample counter
proc_sample_counter: process(clk)
    constant X: unsigned(CNT_BITS-1 downto 0) := (others => '1');
begin
    if rising_edge(clk) then
        sample_cnt_int <= sample_cnt_int + 1;
    end if;
end process;

-- digital rising edges
digital_edge_detect_inst: digital_edge_detect
port map(
    clk       => clk,
    samples_d => samples_d_in,
    rising_d  => rising_d,
    falling_d => falling_d 
);
d1_rising_int <= rising_d(0)(0) & rising_d(1)(0) & rising_d(2)(0) & rising_d(3)(0);
d2_rising_int <= rising_d(0)(1) & rising_d(1)(1) & rising_d(2)(1) & rising_d(3)(1);
d1_falling_int <= falling_d(0)(0) & falling_d(1)(0) & falling_d(2)(0) & falling_d(3)(0);
d2_falling_int <= falling_d(0)(1) & falling_d(1)(1) & falling_d(2)(1) & falling_d(3)(1);

-- analog maximum finder
maxfinder_inst: maxfinder_simple
port map(
    clk             => clk,
    samples_in      => max_samples_in,
    threshold       => a_threshold,
    max_found       => max_found,
    max_pos         => max_pos,
    max_height      => max_height
);
max_samples_in(0) <= samples_a_in_filt(0).data;
max_samples_in(1) <= samples_a_in_filt(1).data;
a_maxfound_int <= (valid => max_found, pos => max_pos);

--------------------------------------------------------------------------------
-- output

-- shift in/out input samples, use queue to align input samples with event outputs
process(clk)
begin
    if rising_edge(clk) then
        -- digital
        samples_d_buf(1 to samples_d_buf'high) <= samples_d_buf(0 to samples_d_buf'high-1);
        samples_d_buf(0) <= samples_d_in;
        samples_d_out <= samples_d_buf(samples_d_buf'high); 
        -- analog
        samples_a_buf(1 to samples_a_buf'high) <= samples_a_buf(0 to samples_a_buf'high-1);
        for I in samples_a_in_filt'low to samples_a_in_filt'high loop
            samples_a_buf(0)(I) <= samples_a_in_filt(I).data;
        end loop;
        samples_a_out <= samples_a_buf(samples_a_buf'high);
    end if;
end process;

-- register event outputs
process(clk)
begin
    if rising_edge(clk) then
        cnt <= sample_cnt_int;
        tdc_events <= (
            d1_rising  => flat_events_to_event_t(d1_rising_int),
            d1_falling => flat_events_to_event_t(d1_falling_int),
            d2_rising  => flat_events_to_event_t(d2_rising_int),
            d2_falling => flat_events_to_event_t(d2_falling_int),
            a_maxfound => a_maxfound_int,
            a_maxvalue => max_height
        );
    end if;
end process;

end tdc_sample_prep_arch;
