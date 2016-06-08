-------------------------------------------------------------------------------
-- FT2232H Sync FIFO Interface
--
-- This component is designed to interface an FT2232H USB chip with two
-- dual-port FIFOs in first-word-fall-through (zero read latency) mode. The
-- FIFOs are used for buffering and (de)serializing data words and for
-- crossing the USB and FPGA clock domains.
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
    -- registers for signals from or to ftdi
    signal qusb_rxf_n, qusb_txe_n: std_logic := '1';
    signal usb_rxf, usb_txe: std_logic;
    signal usb_rd_en, usb_wr_en, usb_rd_en_at_ftdi, usb_wr_en_at_ftdi: std_logic := '0';
    signal usb_d_out, usb_d_in: std_logic_vector(7 downto 0) := (others => '-'); 
    signal int_rd_en, int_wr_en, int_oe: std_logic;
    signal int_d_out: std_logic_vector(7 downto 0);

    signal drive_usb_d: boolean;
    signal fifo_in_wr_en_i, fifo_out_rd_en_i: std_logic;

    type byte_array_t is array(integer range <>) of std_logic_vector(7 downto 0);

    -- data read buffer
    signal rx_data_ring: byte_array_t(3 downto 0) := (others => (others => '-'));
    signal rx_index_rd: unsigned(1 downto 0) := (others => '0');
    signal rx_index_wr: unsigned(1 downto 0) := (others => '0');
    signal rx_count: integer range 0 to rx_data_ring'high := 0;

    -- data write buffer
    signal tx_data_ring: byte_array_t(3 downto 0) := (others => (others => '-'));
    signal tx_index_rd: unsigned(1 downto 0) := (others => '0');
    signal tx_index_wr: unsigned(1 downto 0) := (others => '0');
    signal tx_count: integer range 0 to tx_data_ring'high := 0;

    -- state register
    type state_t is (
        s_reset, s_idle,
        s_switch_to_read, s_read, s_end_read,
        s_write
    );
    signal state, next_state: state_t;

    attribute iob: string;
--  attribute iob of usb_rxf_n: signal is "FORCE";
--  attribute iob of usb_txe_n: signal is "FORCE";
--	attribute iob of usb_wr_n: signal is "FORCE";
--	attribute iob of usb_rd_n: signal is "FORCE";
--	attribute iob of usb_oe_n: signal is "FORCE";
--	attribute iob of usb_d: signal is "FORCE";
--	attribute iob of usb_d_out: signal is "FORCE";
--	attribute iob of usb_d_in: signal is "FORCE";

begin

usb_d <= usb_d_out when drive_usb_d else (others => 'Z');

sync_input: process(usb_clk)
begin
    if rising_edge(usb_clk) then
        if rst = '1' then
            qusb_rxf_n <= '0';
            qusb_txe_n <= '0';
            usb_d_in <= (others => '-');
        else
            qusb_rxf_n <= usb_rxf_n;
            qusb_txe_n <= usb_txe_n;
            usb_d_in <= usb_d;
        end if;
    end if;
end process;
usb_rxf <= not qusb_rxf_n;
usb_txe <= not qusb_txe_n;

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

sync_receive_data: process(usb_clk)
    variable byte_delta: integer range -1 to 1;
begin
    if rising_edge(usb_clk) then
        if rst = '1' then
            rx_count <= 0;
            rx_index_rd <= (others => '0');
            rx_index_wr <= (others => '0');
            rx_data_ring <= (others => (others => '-'));
        else
            byte_delta := 0;
            -- add byte from usb to ring if valid
            if (usb_rd_en_at_ftdi = '1') and (usb_rxf = '1') then
                rx_data_ring(to_integer(rx_index_wr)) <= usb_d_in;
                rx_index_wr <= rx_index_wr + 1;
                byte_delta := byte_delta + 1;
            end if;
            -- remove byte from ring if read from interface
            if (fifo_in_wr_en_i = '1') and (fifo_in_full = '0') then
                rx_index_rd <= rx_index_rd + 1;
                byte_delta := byte_delta - 1;
            end if;
            rx_count <= rx_count + byte_delta;
        end if;
    end if;
end process;
fifo_in_data <= rx_data_ring(to_integer(rx_index_rd)) when rx_count /= 0 else (others => '-');
fifo_in_wr_en_i <= '1' when rx_count /= 0 else '0';
fifo_in_wr_en <= fifo_in_wr_en_i;

sync_transmit_data: process(usb_clk)
    variable byte_delta: integer range -1 to 1;
begin
    if rising_edge(usb_clk) then
        if rst = '1' then
            tx_count <= 0;
            tx_index_rd <= (others => '0');
            tx_index_wr <= (others => '0');
            tx_data_ring <= (others => (others => '-'));
        else
            byte_delta := 0;
            -- add byte from interface
            if (fifo_out_rd_en_i = '1') and (fifo_out_empty = '0') then
                tx_data_ring(to_integer(tx_index_wr)) <= fifo_out_data;
                tx_index_wr <= tx_index_wr + 1;
                byte_delta := byte_delta + 1;
            end if;
            -- advance data pointer at each write
            if int_wr_en = '1' then
                tx_index_rd <= tx_index_rd + 1;
                byte_delta := byte_delta - 1;
            end if;
            -- recover byte from ring if write was not accepted
            if (usb_wr_en_at_ftdi = '1') and (usb_txe = '0') then
                tx_index_rd <= tx_index_rd - 1;
                byte_delta := byte_delta + 1;
            end if;

            tx_count <= tx_count + byte_delta;
        end if;
    end if;
end process;

comb_state: process(state,
                    fifo_in_full, usb_rxf, rx_count,
                    fifo_out_empty, usb_txe, tx_count)
    variable could_wr, could_rd: boolean;
begin
    -- next state
    next_state <= state;
    -- output defaults
    drive_usb_d <= false;
    int_oe <= '0';
    int_rd_en <= '0';
    int_wr_en <= '0';

    -- internal defaults
    fifo_out_rd_en_i <= '0';

    could_wr := (usb_txe = '1') and ((tx_count > 0) or (fifo_out_empty = '0'));
    could_rd := (fifo_in_full = '0') and (usb_rxf = '1') and (rx_count <= 1);
    case state is
        when s_reset =>
            next_state <= s_idle;
        when s_idle =>
            -- switch to write or read mode
            if could_wr then
                next_state <= s_write;
            elsif could_rd then
                next_state <= s_switch_to_read;
            end if;
        when s_switch_to_read =>
            -- disable our outputs and enable usb outputs 
            int_oe <= '1';
            next_state <= s_read;
        when s_read =>
            -- read data from usb
            int_oe <= '1';
            int_rd_en <= '1';
            -- end reading if there is nothing to read or interface won't accpet more data
            if not could_rd then
                int_rd_en <= '0';
                next_state <= s_end_read;
            end if;
        when s_end_read =>
            -- wait until last read command passed 
            if could_wr then
                next_state <= s_write;
            else
                next_state <= s_idle;
            end if;
        when s_write =>
            drive_usb_d <= true;
            if could_wr then
                -- write valid data to usb
                if tx_count > 0 then
                    int_wr_en <= '1'; 
                end if;
                -- fetch data from interface if there is enough space for failed writes
                if tx_count <= 1 then
                    fifo_out_rd_en_i <= '1';
                end if;
            else
                -- end writing if there is nothing to write or usb won't accept more data
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
int_d_out <= tx_data_ring(to_integer(tx_index_rd));
fifo_out_rd_en <= fifo_out_rd_en_i;

sync_output_internal: process(usb_clk)
begin
    if rising_edge(usb_clk) then
        if rst = '1' then
            usb_rd_en <= '0';
            usb_wr_en <= '0';
            usb_rd_en_at_ftdi <= '0';
            usb_wr_en_at_ftdi <= '0';
        else
            usb_rd_en <= int_rd_en;
            usb_wr_en <= int_wr_en;
            usb_rd_en_at_ftdi <= usb_rd_en;
            usb_wr_en_at_ftdi <= usb_wr_en;
        end if;
    end if;
end process;

sync_output: process(usb_clk)
begin
    if rising_edge(usb_clk) then
        if rst = '1' then
            usb_d_out <= (others => '-');
            usb_oe_n <= '1';
            usb_rd_n <= '1';
            usb_wr_n <= '1';
        else
            usb_d_out <= int_d_out;
            usb_oe_n <= not int_oe;
            usb_rd_n <= not int_rd_en;
            usb_wr_n <= not int_wr_en;
        end if;
    end if;
end process;

end ft2232fifo_arch;