library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;
use std.textio.all;

entity ft2232fifo_tb is
end ft2232fifo_tb;

architecture ft2232fifo_tb_arch of ft2232fifo_tb is

    component ft2232fifo
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
    end component;

    signal usb_clk: std_logic := '0';
    signal usb_oe_n: std_logic;
    signal usb_rd_n: std_logic;
    signal usb_wr_n: std_logic;
    signal usb_rxf_n: std_logic := '1';
    signal usb_txe_n: std_logic := '1';
    signal usb_d: std_logic_vector(7 downto 0) := (others => '0');
    signal usb_d_out: std_logic_vector(7 downto 0) := (others => '0');

    signal rst: std_logic := '0';
    signal fifo_in_wr_en: std_logic;
    signal fifo_in_full: std_logic := '1';
    signal fifo_in_data: std_logic_vector(7 downto 0);
    signal fifo_out_rd_en: std_logic;
    signal fifo_out_empty: std_logic := '1';
    signal fifo_out_data: std_logic_vector(7 downto 0) := (others => '0');

    constant clk_period : time := 16 ns;
    
begin

ft2232fifo_inst: ft2232fifo
port map (
    -- ftdi interface
    usb_clk => usb_clk,
    usb_oe_n => usb_oe_n,
    usb_rd_n => usb_rd_n,
    usb_wr_n => usb_wr_n,
    usb_rxf_n => usb_rxf_n,
    usb_txe_n => usb_txe_n,
    usb_d => usb_d,
    -- application/fifo interface
    rst => rst,
    fifo_in_wr_en => fifo_in_wr_en,
    fifo_in_full => fifo_in_full,
    fifo_in_data => fifo_in_data,
    fifo_out_rd_en => fifo_out_rd_en,
    fifo_out_empty => fifo_out_empty,
    fifo_out_data => fifo_out_data
);

clk_process: process
begin
    usb_clk <= '0';
    wait for clk_period/2;
    usb_clk <= '1';
    wait for clk_period/2;
end process;

process(usb_oe_n, usb_d_out, usb_rxf_n)
begin
    usb_d <= (others => 'Z');
    if (usb_oe_n = '0') then
        if (usb_rxf_n = '1') then
            usb_d <= (others => 'X');
        else
            usb_d <= usb_d_out;
        end if; 
    end if;
end process;

data_from_usb: process(usb_clk)
begin
    if rising_edge(usb_clk) then
        if (usb_rd_n = '0') and (usb_rxf_n = '0') then
            usb_d_out <= std_logic_vector(unsigned(usb_d_out) + 1);
        end if;
    end if;
end process;

data_received: process(usb_clk)
    variable data_expected: integer := 0;
    variable data_received: integer;
begin
    if rising_edge(usb_clk) then
        if (fifo_in_wr_en = '1') and (fifo_in_full = '0') then
            data_received := to_integer(unsigned(fifo_in_data));
            report "RX: " & integer'image(data_received);
            assert (data_received = data_expected) report "recieved bad data" severity failure;
            data_expected := data_expected + 1;
        end if;
    end if;
end process;

data_from_fifo: process(usb_clk)
begin
    if rising_edge(usb_clk) then
        if (fifo_out_rd_en = '1') and (fifo_out_empty = '0') then
            fifo_out_data <= std_logic_vector(unsigned(fifo_out_data) + 1);
        end if;
    end if;
end process;

data_transmitted: process(usb_clk)
    variable data_expected: integer := 0;
    variable data_transmitted: integer;
begin
    if rising_edge(usb_clk) then
        if (usb_wr_n = '0') and (usb_txe_n = '0') then
            data_transmitted := to_integer(unsigned(usb_d));
            report "TX: " & integer'image(data_transmitted);
            assert (data_transmitted = data_expected) report "transmitted bad data" severity failure;
            data_expected := data_expected + 1;
        end if;
    end if;
end process;

stimulus: process
    constant usb_txe_n_pattern:      std_logic_vector := "111100000011111111110000000000000000000000";
    constant usb_rxf_n_pattern:      std_logic_vector := "111111111111111111111110000000000000001111";
    constant fifo_in_full_pattern:   std_logic_vector := "000000000000000000000000000000000000000000";
    constant fifo_out_empty_pattern: std_logic_vector := "000000000000000000000000000111000000000000";
begin
    usb_txe_n <= usb_txe_n_pattern(0);
    usb_rxf_n <= usb_rxf_n_pattern(0);
    fifo_in_full <= fifo_in_full_pattern(0);
    fifo_out_empty <= fifo_out_empty_pattern(0);
    for i in usb_txe_n_pattern'range loop
        wait for clk_period;
        usb_txe_n <= usb_txe_n_pattern(i);
        usb_rxf_n <= usb_rxf_n_pattern(i);
        fifo_in_full <= fifo_in_full_pattern(i);
        fifo_out_empty <= fifo_out_empty_pattern(i);
    end loop;

    assert false report "Stimulus finished" severity note;
    wait;
end process;

end ft2232fifo_tb_arch;
