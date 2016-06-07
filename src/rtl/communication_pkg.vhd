library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package communication_pkg is

    constant COMM_BUS_WIDTH: integer := 16;

    type comm_to_slave_t is record
        rd_req: std_logic;
        wr_req: std_logic;
        data_wr: std_logic_vector(COMM_BUS_WIDTH-1 downto 0);
    end record;

    type comm_from_slave_t is record
        rd_ack: std_logic;
        wr_ack: std_logic;
        data_rd: std_logic_vector(COMM_BUS_WIDTH-1 downto 0);
    end record;

end communication_pkg;

package body communication_pkg is
end communication_pkg;
