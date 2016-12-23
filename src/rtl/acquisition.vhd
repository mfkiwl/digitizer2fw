-------------------------------------------------------------------------------
-- Digitizer2 acquisition logic
--
-- Author: Peter Würtz, TU Kaiserslautern (2016)
-- Distributed under the terms of the GNU General Public License Version 3.
-- The full license is in the file COPYING.txt, distributed with this software.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sampling_pkg.all;
use work.maxfinder_pkg.all;
use work.tdc_sample_prep_pkg.all;


entity acquisition is
generic ( TDC_CNT_BITS: natural := 22 );
port (
    -- acquisition domain
    clk_samples: in std_logic;
    samples_d_in: in din_samples_t(0 to 3);
    samples_a_in: in adc_samples_t(0 to 1);
    a_threshold: in a_sample_t;
    a_invert: in std_logic;
    a_average: in std_logic_vector(1 downto 0);
    acq_mode: in std_logic_vector(1 downto 0);
    acq_start_src: in std_logic_vector(2 downto 0);
    acq_stop_src: in std_logic_vector(2 downto 0);
    acq_reset: in std_logic;
    acq_stop: in std_logic;
    acq_state: out std_logic_vector(2 downto 0);
    -- application domain
    clk_rd: in std_logic;
    rd_en: in std_logic;
    rd_empty: out std_logic;
    rd_data: out std_logic_vector(15 downto 0);
    rd_2xcnt: out std_logic_vector(15 downto 0)
);
end acquisition;

architecture acquisition_arch of acquisition is

    component tdc_sample_prep is
    generic ( CNT_BITS: natural := TDC_CNT_BITS );
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
    signal tdc_d : din_samples_t ( 0 to 3 );
    signal tdc_a : a_samples_t ( 0 to 1 );
    signal tdc_cnt : unsigned ( TDC_CNT_BITS-1 downto 0 );
    signal tdc_events : tdc_events_t;

    component fifo_adc_core
    port (
        rst: in std_logic;
        wr_clk: in std_logic;
        rd_clk: in std_logic;
        din : IN std_logic_vector(31 downto 0);
        wr_en: in std_logic;
        rd_en: in std_logic;
        dout : out std_logic_vector(15 downto 0);
        full: out std_logic;
        empty: out std_logic;
        rd_data_count: out std_logic_vector(16 downto 0)
    );
    end component;
    signal acq_buffer_din: std_logic_vector(31 downto 0);
    signal acq_buffer_dout: std_logic_vector(15 downto 0);
    signal acq_buffer_rst: std_logic;
    signal acq_buffer_full: std_logic;
    signal acq_buffer_empty: std_logic;
    signal acq_buffer_rd: std_logic;
    signal acq_buffer_wr: std_logic;
    signal acq_buffer_rd_cnt: std_logic_vector(16 downto 0);

begin

tdc_sample_prep_inst: tdc_sample_prep
generic map (CNT_BITS => TDC_CNT_BITS)
port map(
    clk           => clk_samples,
    samples_d_in  => samples_d_in,
    samples_a_in  => samples_a_in,
    a_threshold   => a_threshold,
    a_invert      => a_invert,
    a_average     => a_average,
    samples_d_out => tdc_d,
    samples_a_out => tdc_a,
    cnt           => tdc_cnt,
    tdc_events    => tdc_events
);

fifo_acq_inst: fifo_adc_core
port map (
    rst => acq_buffer_rst,
    wr_clk => clk_samples,
    rd_clk => clk_rd,
    din => acq_buffer_din,
    wr_en => acq_buffer_wr,
    rd_en => acq_buffer_rd,
    dout => acq_buffer_dout,
    full => acq_buffer_full,
    empty => acq_buffer_empty,
    rd_data_count => acq_buffer_rd_cnt
);
rd_empty <= acq_buffer_empty;
rd_data <= acq_buffer_dout;
acq_buffer_rd <= rd_en;
rd_2xcnt <= acq_buffer_rd_cnt(acq_buffer_rd_cnt'high downto 1);

acquisition_process: process(clk_samples)    
    type event_source_map_t is array(integer range 0 to 6) of std_logic;
    variable event_source_map: event_source_map_t;
    
    type acq_state_t is (s_reset, s_wait_ready, s_waittrig, s_buffering, s_done);
    variable tdc_cnt_zero: unsigned(tdc_cnt'range) := (others => '0');
    variable acq_state_int: acq_state_t := s_reset;
    variable tdc_cnt_ovfl: std_logic := '0';
    variable start_trig: boolean := false;
    variable stop_trig: boolean := false;
begin
    if rising_edge(clk_samples) then
        -- reset acquisition fifo when in reset state
        if acq_state_int = s_reset then
            acq_buffer_rst <= '1';
        else
            acq_buffer_rst <= '0';
        end if;

        -- counter overflow event
        if tdc_cnt = tdc_cnt_zero then
            tdc_cnt_ovfl := '1';
        else
            tdc_cnt_ovfl := '0';
        end if;

        -- map of start/stop event sources
        event_source_map := (
            0 => tdc_cnt_ovfl,
            1 => tdc_events.d1_rising.valid,
            2 => tdc_events.d1_falling.valid,
            3 => tdc_events.d2_rising.valid,
            4 => tdc_events.d2_falling.valid,
            5 => tdc_events.a_maxfound.valid,
            6 => '0'
        );

        -- start trigger from selected event source
        start_trig := event_source_map(to_integer(unsigned(acq_start_src))) = '1';
        stop_trig  := (event_source_map(to_integer(unsigned(acq_stop_src))) = '1') or (acq_stop = '1');

        -- state machine
        case acq_state_int is
            when s_reset =>
                acq_state_int := s_wait_ready;
            when s_wait_ready =>
                if acq_buffer_full = '0' then
                    acq_state_int := s_waittrig;
                end if;
            when s_waittrig =>
                if start_trig then
                    acq_state_int := s_buffering;
                end if;
            when s_buffering =>
                if acq_buffer_full = '1' or stop_trig then
                    acq_state_int := s_done;
                end if;
            when others =>
                null;
        end case;
        -- always go to reset state when acq_reset is high
        if acq_reset = '1' then
            acq_state_int := s_reset;
        end if;
        
        -- select signals for fifo input
        acq_buffer_wr <= '0';
        acq_buffer_din <= (others => '0');
        case acq_mode is
        when "00" =>
            -- raw sample mode (digital + analog)
            acq_buffer_din <= tdc_d(0)(0) & tdc_d(1)(0) & tdc_d(2)(0) & tdc_d(3)(0) & std_logic_vector(tdc_a(0)) &
                              tdc_d(0)(1) & tdc_d(1)(1) & tdc_d(2)(1) & tdc_d(3)(1) & std_logic_vector(tdc_a(1));
            acq_buffer_wr <= '1';
        when "01" =>
            -- maxfind debug mode (analog + single digital + maxfind)
            acq_buffer_din <= tdc_d(0)(0) & tdc_d(1)(0) & tdc_d(2)(0) & tdc_d(3)(0) & std_logic_vector(tdc_a(0)) &
                              '0' & to_std_logic_vector(tdc_events.a_maxfound) & std_logic_vector(tdc_a(1));
            acq_buffer_wr <= '1';
        when "10" =>
            -- TDC mode (counter + events)
            acq_buffer_din <= tdc_cnt_ovfl &                               -- overflow(31)
                              to_std_logic_vector(tdc_events.a_maxfound) & -- valid(30) + pos(29-28)
                              to_std_logic_vector(tdc_events.d1_rising) &  -- valid(27) + pos(26-25)
                              to_std_logic_vector(tdc_events.d2_rising) &  -- valid(24) + pos(23-22)
                              std_logic_vector(tdc_cnt);                   -- cnt(21-0)
            acq_buffer_wr <= tdc_cnt_ovfl or tdc_events.d1_rising.valid or tdc_events.d2_rising.valid or tdc_events.a_maxfound.valid;
        when others =>
            -- TDC + height mode (counter + maxvalue)
            acq_buffer_din <= (others => '0');
            if tdc_events.a_maxfound.valid = '1' then
                -- use only the last 10 bits from maxvalue (assume non-negative value -> unsigned 10bit)
                acq_buffer_din(31 downto 22) <= std_logic_vector(tdc_events.a_maxvalue(9 downto 0));
            end if;
            acq_buffer_din(21 downto 0) <= std_logic_vector(tdc_cnt);
            acq_buffer_wr <= tdc_cnt_ovfl or tdc_events.a_maxfound.valid;
        end case;
        
        -- override data valid if not in buffering state
        if acq_state_int /= s_buffering then
            acq_buffer_wr <= '0';
        end if;

        -- write state to global register, converted to unsigned/slv
        acq_state <= std_logic_vector(to_unsigned(acq_state_t'pos(acq_state_int), 3));
    end if;
end process;

end acquisition_arch;
