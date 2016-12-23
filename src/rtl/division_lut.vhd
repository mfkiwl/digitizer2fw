-------------------------------------------------------------------------------
-- Division lookup table for unsigned values
--
-- Author: Peter Würtz, TU Kaiserslautern (2016)
-- Distributed under the terms of the GNU General Public License Version 3.
-- The full license is in the file COPYING.txt, distributed with this software.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

entity division_lut is
    generic (ROUND_FLOAT: boolean := TRUE);
    port (
        clk: in std_logic;
        clk_en: in std_logic;
        divisor: in unsigned;
        result: out unsigned
    );
end division_lut;

architecture division_lut_arch of division_lut is
    constant N_DIVISOR_BITS: natural := divisor'length;
    constant N_RESULT_BITS: natural := result'length;

    type lut_t is array(0 to 2**N_DIVISOR_BITS-1) of unsigned(N_RESULT_BITS-1 downto 0);
    function init_func return lut_t is
        constant factor: real := real(2**(N_RESULT_BITS-1));
        variable frac: real;
        variable frac_repr: natural;
        variable result: lut_t;
    begin
        result(0) := to_unsigned(0, (N_RESULT_BITS));
        for I in 1 to lut_t'high loop
            frac := 1.0/real(I);
            if ROUND_FLOAT then
                frac_repr := natural(round(frac*factor));
            else
                frac_repr := natural(floor(frac*factor));
            end if;
            result(I) := to_unsigned(frac_repr, N_RESULT_BITS);
        end loop;
    return result;
    end function;

    constant lut: lut_t := init_func;
begin

process(clk)
begin
    if rising_edge(clk) then
        if clk_en = '1' then
            result <= lut(to_integer(divisor));
        end if;
    end if;
end process;

end division_lut_arch;

