-- Testbench for fluart: the featureless UART
-- Copyright 2019, 2020 Marc Joosen

-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
-- 
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
-- 
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <https://www.gnu.org/licenses/>.

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity fluart_tb is
end;

architecture testbench of fluart_tb is
	constant CLK_RATIO:	integer := 2;
	constant BRK_LEN:	integer := 15;

	signal clk:		std_logic := '0';
	signal reset:		std_logic := '0';

	signal txd:		std_logic;
	signal rxd:		std_logic := '0';

	signal tx_data:		std_logic_vector(7 downto 0);
	signal tx_req:		std_logic := '0';
	signal tx_brk:		std_logic;
	signal tx_busy:		std_logic;
	signal tx_end:		std_logic;
	signal rx_data:		std_logic_vector(7 downto 0);
	signal rx_data_valid:	std_logic;
	signal rx_brk:		std_logic;
	signal rx_err:		std_logic;

	signal rx_force:	std_logic;

begin
	clk <= not clk after 10 ns;
	reset <= '1', '0' after 30 ns;

	rxd <= txd xor rx_force;

	process
	begin
		tx_brk <= '0';
		rx_force <= '0';
		wait for 100 ns;
		tx_data <= "01001101";
		tx_req <= '1';
		wait for 20 ns;
		tx_req <= '0';
		wait until rx_data_valid = '1';
		wait for 100 ns;
		if rx_data = x"4d" then
			assert false report "OK" severity note;	-- stop
		else
			assert false report "fail!" severity failure;	-- stop
		end if;

		-- send break
		tx_brk <= '1';
		wait for 20 ns;
		tx_brk <= '0';
		wait until tx_end = '1';

		-- runt break -> rx_error
		wait for 100 ns;
		rx_force <= '1';
		wait for (BRK_LEN - 1) * CLK_RATIO * 20 ns;
		rx_force <= '0';

		-- long break
		wait for 100 ns;
		rx_force <= '1';
		wait for (BRK_LEN + 2) * CLK_RATIO * 20 ns;
		rx_force <= '0';

		wait;
	end process;

	dut: entity work.fluart
		generic map(
			CLK_FREQ => CLK_RATIO,	-- main frequency (Hz)
			SER_FREQ => 1,		-- bit rate (bps)
			BRK_LEN  => BRK_LEN
		)
		port map (
			clk	=> clk,
			reset	=> reset,

			txd	=> txd,
			rxd	=> rxd,

			tx_data		=> tx_data,
			tx_req		=> tx_req,
			tx_brk		=> tx_brk,
			tx_busy		=> tx_busy,
			tx_end		=> tx_end,
			rx_data		=> rx_data,
			rx_data_valid	=> rx_data_valid,
			rx_brk		=> rx_brk,
			rx_err		=> rx_err
		);

end;
