-------------------------------------------------------------------------------
-- Maximum finder, base module
--
-- Finds maxima between two samples by checking for zero crossing of finite
-- differences.
--
-- The window length N_WINDOW_LENGTH defines the number of incoming samples per
-- clock cycle, each sample being a signed number with a size of N_SAMPLE_BITS.
-- It is possible to search for multiple maxima per window by splitting the
-- initial window length into N_OUTPUTS segments.
--
-- | sample0 sample1 sample2 sample3 | sample4 sample5 sample6 sample7 |
-- | maximum find 0                  | maximum find 1                  |
--
-- 'samples': N_WINDOW_LENGTH signed samples of N_SAMPLE_BITS, first sample at 0
-- 'threshold': Signed number of N_SAMPLE_BITS bits
-- 'max_found': N_OUTPUTS bits of '1' if a maximum was found in the n'th search
--              segment, else '0'
-- 'max_pos': N_OUTPUTS unsigned values of N_POS_BITS, specifying the position
--            left of a valid maximum within the n'th segment
--            (value for first segment at 0)
-- 'max_adiff0/1': N_OUTPUTS unsigned values of N_SAMPLE_BITS, specifying the
--                 absolute values of the finite differences left and right of
--                 a maximum within the n'th segment
--                 (values for first segment at 0)
-- 'max_sample0/1': N_OUTPUTS signed values of N_SAMPLE_BITS, specifying the
--                  original sample values left and right of
--                  a maximum within the n'th segment
--                  (values for first segment at 0)
-- 
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work;
use work.maxfinder_pkg.all;

entity maxfinder_base is
    generic(
        N_WINDOW_LENGTH: natural;
        N_OUTPUTS: natural := 1;
        N_SAMPLE_BITS: natural := 12;
        SYNC_STAGE1: boolean := FALSE;
        SYNC_STAGE2: boolean := FALSE;
        SYNC_STAGE3: boolean := TRUE
    );
    port (
        clk: in std_logic;
        samples: in std_logic_vector(N_WINDOW_LENGTH*N_SAMPLE_BITS-1 downto 0);
        threshold: in std_logic_vector(N_SAMPLE_BITS-1 downto 0);
        max_found: out std_logic_vector(N_OUTPUTS-1 downto 0);
        max_pos: out std_logic_vector(N_OUTPUTS*log2ceil(N_WINDOW_LENGTH/N_OUTPUTS)-1 downto 0);
        max_adiff0: out std_logic_vector(N_OUTPUTS*N_SAMPLE_BITS-1 downto 0);
        max_adiff1: out std_logic_vector(N_OUTPUTS*N_SAMPLE_BITS-1 downto 0);
        max_sample0: out std_logic_vector(N_OUTPUTS*N_SAMPLE_BITS-1 downto 0);
        max_sample1: out std_logic_vector(N_OUTPUTS*N_SAMPLE_BITS-1 downto 0)
    );
end maxfinder_base;

architecture maxfinder_base_arch of maxfinder_base is
    constant N_POS_PER_OUTPUT: natural := N_WINDOW_LENGTH / N_OUTPUTS;
    constant N_POS_BITS: natural := log2ceil(N_WINDOW_LENGTH/N_OUTPUTS);

    type samples_t is array(natural range <>) of signed(N_SAMPLE_BITS-1 downto 0);
    type samples_diff_t is array(natural range <>) of signed(N_SAMPLE_BITS+1-1 downto 0);
    type samples_adiff_t is array(natural range <>) of unsigned(N_SAMPLE_BITS-1 downto 0);
    type pos_arr_t is array(natural range <>) of unsigned(N_POS_BITS-1 downto 0);

    -- stage0
    signal s0_samples_in: samples_t(0 to N_WINDOW_LENGTH+4-1) := (others => (others => '0'));

    -- stage1
    signal s1_samples_in: samples_t(0 to N_WINDOW_LENGTH+1-1) := (others => (others => '0'));
    signal s1_samples_diff: samples_diff_t(0 to N_WINDOW_LENGTH+2-1) := (others => (others => '0'));
    signal s1_above_threshold: std_logic_vector(N_WINDOW_LENGTH-1 downto 0) := (others => '0');
    procedure stage1(signal s0_samples_in: in samples_t;
                     signal threshold: in std_logic_vector;
                     signal s1_samples_in: out samples_t;
                     signal s1_samples_diff: out samples_diff_t;
                     signal s1_above_threshold: out std_logic_vector) is
    begin
        -- calculate finite differences
        for i in 0 to N_WINDOW_LENGTH+2-1 loop
            s1_samples_diff(i) <= resize(s0_samples_in(i+2), N_SAMPLE_BITS+1) - resize(s0_samples_in(i), N_SAMPLE_BITS+1);
        end loop;
        -- check if samples are above threshold
        for i in 0 to N_WINDOW_LENGTH-1 loop
            if s0_samples_in(i+2) > signed(threshold) then
                s1_above_threshold(i) <= '1';
            else
                s1_above_threshold(i) <= '0';
            end if;
        end loop;
        -- forward samples_in to next stage
        s1_samples_in <= s0_samples_in(2 to s0_samples_in'high-1);
    end stage1;

    -- stage2
    signal s2_samples_in: samples_t(0 to N_WINDOW_LENGTH+1-1);
    signal s2_samples_diff: samples_diff_t(0 to N_WINDOW_LENGTH+1-1) := (others => (others => '0'));
    signal s2_max_criterion: std_logic_vector(N_WINDOW_LENGTH-1 downto 0) := (others => '0');
    procedure stage2(signal s1_samples_in: in samples_t;
                     signal s1_samples_diff: in samples_diff_t;
                     signal s1_above_threshold: in std_logic_vector;
                     signal s2_samples_diff: out samples_diff_t;
                     signal s2_samples_in: out samples_t;
                     signal s2_max_criterion: out std_logic_vector) is
        variable s_left, s_center, s_right, s_valid, s_max: boolean;
    begin
        -- check criterion for maximum between i and i+1
        for i in 0 to N_WINDOW_LENGTH-1 loop
            s_left   := s1_samples_diff(i+0) >= 0;
            s_center := s1_samples_diff(i+1) >= 0;
            s_right  := s1_samples_diff(i+2) < 0;
            s_valid  := s1_above_threshold(i) = '1';
            s_max := s_left and s_center and s_right and s_valid;
            if s_max then
                s2_max_criterion(i) <= '1';
            else
                s2_max_criterion(i) <= '0';
            end if;
        end loop;
        -- forward samples_diff to next stage
        s2_samples_diff <= s1_samples_diff(1 to s1_samples_diff'high);
        -- forward samples_in to next stage
        s2_samples_in <= s1_samples_in;
    end stage2;

    -- stage3
    signal s3_found: std_logic_vector(N_OUTPUTS-1 downto 0);
    signal s3_pos: pos_arr_t(N_OUTPUTS-1 downto 0);
    signal s3_adiff0: samples_adiff_t(N_OUTPUTS-1 downto 0);
    signal s3_adiff1: samples_adiff_t(N_OUTPUTS-1 downto 0);
    signal s3_sample0: samples_t(N_OUTPUTS-1 downto 0);
    signal s3_sample1: samples_t(N_OUTPUTS-1 downto 0);
    procedure stage3(signal s2_samples_diff: in samples_diff_t;
                     signal s2_samples_in: in samples_t;
                     signal s2_max_criterion: in std_logic_vector;
                     signal s3_found: out std_logic_vector;
                     signal s3_pos: out pos_arr_t;
                     signal s3_adiff0: out samples_adiff_t;
                     signal s3_adiff1: out samples_adiff_t;
                     signal s3_sample0: out samples_t;
                     signal s3_sample1: out samples_t) is
        variable i: natural;
        variable diff1_positive: signed(N_SAMPLE_BITS downto 0);
    begin
        -- for each output..
        for i_o in 0 to N_OUTPUTS-1 loop
            -- default to not valid / don't care
            s3_found(i_o) <= '0';
            s3_pos(i_o) <= (others => '-');
            s3_adiff0(i_o) <= (others => '-');
            s3_adiff1(i_o) <= (others => '-');
            s3_sample0(i_o) <= (others => '-');
            s3_sample1(i_o) <= (others => '-');
            -- check all positions within output for maxima
            -- store the last one that is valid
            for i_p in 0 to N_POS_PER_OUTPUT-1 loop
                i := i_o*N_POS_PER_OUTPUT + i_p;
                if s2_max_criterion(i) = '1' then
                    s3_found(i_o) <= '1';
                    s3_pos(i_o) <= to_unsigned(i_p, N_POS_BITS);
                    s3_adiff0(i_o) <= unsigned(s2_samples_diff(i)(N_SAMPLE_BITS-1 downto 0));
                    diff1_positive := -s2_samples_diff(i+1);
                    s3_adiff1(i_o) <= unsigned(diff1_positive(N_SAMPLE_BITS-1 downto 0));
                    s3_sample0(i_o) <= s2_samples_in(i);
                    s3_sample1(i_o) <= s2_samples_in(i+1);
                end if;
            end loop;
        end loop;
    end stage3;
begin

-------------------------------------------------------------------------------

stage0: process(clk)
begin
    if rising_edge(clk) then
        -- shift buffer
        s0_samples_in(0 to 3) <= s0_samples_in(s0_samples_in'high-3 to s0_samples_in'high);
        -- add new samples at the end
        for i in 0 to N_WINDOW_LENGTH-1 loop
            s0_samples_in(4+i) <= signed(samples((i+1)*N_SAMPLE_BITS-1 downto i*N_SAMPLE_BITS));
        end loop;        
    end if;
end process;

-------------------------------------------------------------------------------

GEN_SYNC_STAGE1: if SYNC_STAGE1 generate
process(clk)
begin
    if rising_edge(clk) then
        stage1(s0_samples_in, threshold,
               s1_samples_in, s1_samples_diff, s1_above_threshold);
    end if;
end process;
end generate GEN_SYNC_STAGE1;

GEN_ASYNC_STAGE1: if not SYNC_STAGE1 generate
process(s0_samples_in, threshold, s1_samples_in, s1_samples_diff, s1_above_threshold)
begin
    stage1(s0_samples_in, threshold,
           s1_samples_in, s1_samples_diff, s1_above_threshold);
end process;
end generate GEN_ASYNC_STAGE1;

-------------------------------------------------------------------------------

GEN_SYNC_STAGE2: if SYNC_STAGE2 generate
process(clk)
begin
    if rising_edge(clk) then
        stage2(s1_samples_in, s1_samples_diff, s1_above_threshold,
               s2_samples_diff, s2_samples_in, s2_max_criterion);
    end if;
end process;
end generate GEN_SYNC_STAGE2;

GEN_ASYNC_STAGE2: if not SYNC_STAGE2 generate
process(s1_samples_in, s1_samples_diff, s1_above_threshold, s2_samples_diff, s2_samples_in, s2_max_criterion)
begin
    stage2(s1_samples_in, s1_samples_diff, s1_above_threshold,
           s2_samples_diff, s2_samples_in, s2_max_criterion);
end process;
end generate GEN_ASYNC_STAGE2;

-------------------------------------------------------------------------------

GEN_SYNC_STAGE3: if SYNC_STAGE3 generate
process(clk)
begin
    if rising_edge(clk) then
        stage3(s2_samples_diff, s2_samples_in, s2_max_criterion,
               s3_found, s3_pos, s3_adiff0, s3_adiff1, s3_sample0, s3_sample1);
    end if;
end process;
end generate GEN_SYNC_STAGE3;

GEN_ASYNC_STAGE3: if not SYNC_STAGE3 generate
process(s2_samples_diff, s2_samples_in, s2_max_criterion)
begin
    stage3(s2_samples_diff, s2_samples_in, s2_max_criterion,
           s3_found, s3_pos, s3_adiff0, s3_adiff1, s3_sample0, s3_sample1);
end process;
end generate GEN_ASYNC_STAGE3;

-------------------------------------------------------------------------------

map_s3_to_out: process(s3_found, s3_pos, s3_adiff0, s3_adiff1, s3_sample0, s3_sample1)
begin
    for i_o in 0 to N_OUTPUTS-1 loop
        -- register the output segment within final output vector
        max_found(i_o) <= s3_found(i_o);
        max_pos((i_o+1)*N_POS_BITS-1 downto i_o*N_POS_BITS) <= std_logic_vector(s3_pos(i_o));
        max_adiff0((i_o+1)*N_SAMPLE_BITS-1 downto i_o*N_SAMPLE_BITS) <= std_logic_vector(s3_adiff0(i_o));
        max_adiff1((i_o+1)*N_SAMPLE_BITS-1 downto i_o*N_SAMPLE_BITS) <= std_logic_vector(s3_adiff1(i_o));
        max_sample0((i_o+1)*N_SAMPLE_BITS-1 downto i_o*N_SAMPLE_BITS) <= std_logic_vector(s3_sample0(i_o));
        max_sample1((i_o+1)*N_SAMPLE_BITS-1 downto i_o*N_SAMPLE_BITS) <= std_logic_vector(s3_sample1(i_o));
    end loop;
end process;

end maxfinder_base_arch;
