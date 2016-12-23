-------------------------------------------------------------------------------
-- Detect rising/falling edges in digital input samples
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.sampling_pkg.all;

entity digital_edge_detect is
port (
    clk: in std_logic;
    samples_d: in din_samples_t(0 to 3);
    rising_d: out din_samples_t(0 to 3);
    falling_d: out din_samples_t(0 to 3)
);
end digital_edge_detect;

architecture digital_edge_detect_arch of digital_edge_detect is
    signal samples_d_buffered: din_samples_t(0 to 4) := (others => (others => '0'));
begin

buffer_signal: process(clk)
begin
    if rising_edge(clk) then
        samples_d_buffered(0) <= samples_d_buffered(4);
        samples_d_buffered(1 to 4) <= samples_d;
    end if;
end process;

find_rising_edges: process(clk)
begin
    if rising_edge(clk) then
        for I in 0 to 3 loop
        for CH in samples_d_buffered(I)'low to samples_d_buffered(I)'high loop
            if samples_d_buffered(I)(CH) = '0' and samples_d_buffered(I+1)(CH) = '1' then
                rising_d(I)(CH) <= '1';
            else
                rising_d(I)(CH) <= '0';
            end if;
        end loop;
        end loop;
    end if;
end process;

find_falling_edges: process(clk)
begin
    if rising_edge(clk) then
        for I in 0 to 3 loop
        for CH in samples_d_buffered(I)'low to samples_d_buffered(I)'high loop
            if samples_d_buffered(I)(CH) = '1' and samples_d_buffered(I+1)(CH) = '0' then
                falling_d(I)(CH) <= '1';
            else
                falling_d(I)(CH) <= '0';
            end if;
        end loop;
        end loop;
    end if;
end process;

end digital_edge_detect_arch;
