-------------------------------------------------------------------------------
-- FT2232H Sync FIFO Interface
--
-- This component is designed to interface an FT2232H USB chip with two
-- dual-port FIFOs in first-word-fall-through (zero read latency) mode. The
-- FIFOs are used for buffering and (de)serializing data words and for
-- crossing the USB and FPGA clock domains.
--
-- Author: Peter Würtz, TU Kaiserslautern (2016)
-- Distributed under the terms of the GNU General Public License Version 3.
-- The full license is in the file COPYING.txt, distributed with this software.
-------------------------------------------------------------------------------

library unisim;
use unisim.vcomponents.all;

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity ft2232fifo is
    port (
        -- ftdi interface
        usb_clk: in std_logic;
        usb_oe_n: out std_logic;
        usb_rd_n: out std_logic;
        usb_wr_n: out std_logic;
        usb_rxf_n: in std_logic;
        usb_txe_n: in std_logic;
        usb_d: inout std_logic_vector(7 downto 0);
        -- application/fifo interface
        rst: in std_logic;
        fifo_in_wr_en: out std_logic;
        fifo_in_full: in std_logic;
        fifo_in_data: out std_logic_vector(7 downto 0);
        fifo_out_rd_en: out std_logic;
        fifo_out_empty: in std_logic;
        fifo_out_data: in std_logic_vector(7 downto 0)
    );
end ft2232fifo;

architecture ft2232fifo_arch of ft2232fifo is
    signal usb_rd_en, usb_wr_en: std_logic;
    signal sfifo_out_rd_en: std_logic;

    -- data read registers
    signal qdata_in: std_logic_vector(7 downto 0) := (others => '-');
    signal qdata_in_valid: std_logic := '0';
    
    -- data write registers
    signal qdata_out: std_logic_vector(7 downto 0) := (others => '-');
    signal qdata_out_valid: std_logic := '0';

    -- state register
    type state_t is (
        s_reset, s_idle,
		  s_read_mode, s_write_mode,
        s_switch_to_write1, s_switch_to_write2, s_switch_to_read
    );
    signal state, next_state: state_t;

begin

usb_rd_n <= not usb_rd_en;
usb_wr_n <= not usb_wr_en;
fifo_in_data <= qdata_in;
fifo_in_wr_en <= qdata_in_valid;
fifo_out_rd_en <= sfifo_out_rd_en;

sync_state: process(usb_clk)
begin
    if rising_edge(usb_clk) then
        if rst = '1' then
            state <= s_reset;
        else
            state <= next_state;
        end if;
    end if;
end process;

sync_data_in: process(usb_clk)
begin
    if rising_edge(usb_clk) then
        if rst = '1' then
            qdata_in_valid <= '0';
            qdata_in <= (others => '-');
        elsif (usb_rd_en = '1') and (usb_rxf_n = '0') then
            -- new data word from usb
            qdata_in_valid <= '1';
            qdata_in <= usb_d;
        elsif (qdata_in_valid = '1') and (fifo_in_full = '0') then
            -- data word consumed by fifo and no new data from usb
            qdata_in_valid <= '0';
            qdata_in <= (others => '-');
        end if;
    end if;
end process;

sync_data_out: process(usb_clk)
begin
    if rising_edge(usb_clk) then
        if rst = '1' then
            qdata_out_valid <= '0';
            qdata_out <= (others => '-');
        elsif (sfifo_out_rd_en = '1') and (fifo_out_empty = '0') then
            -- new data word from fifo
            qdata_out_valid <= '1';
            qdata_out <= fifo_out_data;
        elsif (usb_wr_en = '1') and (usb_txe_n = '0') then
            -- data word consumed by usb and no new data from fifo
            qdata_out_valid <= '0';
            qdata_out <= (others => '-');
        end if;
    end if;
end process;

comb_state: process(state, usb_rxf_n, usb_txe_n, qdata_out, qdata_out_valid, fifo_in_full)
    variable could_wr, could_rd: boolean;
begin
    -- next state
    next_state <= state;
    -- output defaults
    usb_oe_n <= '1';
    usb_rd_en <= '0';
    usb_wr_en <= '0';
    usb_d <= (others => 'Z');
    -- always read from fifo if qdata_out is empty
    sfifo_out_rd_en <= not qdata_out_valid;

    could_wr := (qdata_out_valid = '1') and (usb_txe_n = '0');
    could_rd := (fifo_in_full = '0') and (usb_rxf_n = '0');
    case state is
        when s_reset =>
            next_state <= s_idle;
		  when s_idle =>
		      if could_wr then
					next_state <= s_switch_to_write1;
				elsif could_rd then
					next_state <= s_switch_to_read;
				end if;
        when s_switch_to_read =>
            -- disable our outputs and enable usb outputs 
            next_state <= s_read_mode;
            usb_oe_n <= '0';
        when s_read_mode =>
            -- read data from usb if fifo accepts it
            usb_oe_n <= '0';
            usb_rd_en <= not fifo_in_full;
            -- end read mode if there is nothing to read
				if not could_rd then
					if could_wr then
						next_state <= s_switch_to_write1;
					else
						next_state <= s_idle;
					end if;
				end if;
        when s_switch_to_write1 => 
            -- disable usb output for write mode
            next_state <= s_switch_to_write2;
        when s_switch_to_write2 =>
            -- wait one cycle before enabling our output
            next_state <= s_write_mode;
        when s_write_mode =>
            -- write to usb if valid, get next word from fifo if usb accepts data
            usb_d <= qdata_out;
            if (qdata_out_valid = '1') then
                usb_wr_en <= qdata_out_valid;
                sfifo_out_rd_en <= not usb_txe_n;
            end if;
            -- end write mode if there is nothing to write
				if not could_wr then
					if could_rd then
						next_state <= s_switch_to_read;
					else
						next_state <= s_idle;
					end if;
				end if;
        when others =>
            null;
    end case;
    
end process;

end ft2232fifo_arch;