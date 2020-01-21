-- fluart: the featureless UART
-- Very simple UART, inspired by https://github.com/freecores/rs232_interface
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

entity fluart is
	generic (
		CLK_FREQ:	integer := 50_000_000;	-- main frequency (Hz)
		SER_FREQ:	integer := 115200;	-- bit rate (bps), any number up to CLK_FREQ / 2
		BRK_LEN:	integer := 10		-- break duration (tx), minimum break duration (rx) in bits
	);
	port (
		clk:		in  std_logic;
		reset:		in  std_logic;

		rxd:		in  std_logic;
		txd:		out std_logic;

		tx_data:	in  std_logic_vector(7 downto 0);
		tx_req:		in  std_logic;
		tx_brk:		in  std_logic;
		tx_busy:	out std_logic;
		tx_end:		out std_logic;
		rx_data:	out std_logic_vector(7 downto 0);
		rx_data_valid:	out std_logic;
		rx_brk:		out std_logic;
		rx_err:		out std_logic
	);

begin
	assert BRK_LEN >= 10 report "BRK_LEN must be >= 10" severity failure;
end;


architecture rtl of fluart is

	type state is (idle, start, data, stop1, stop2, break);

	constant CLK_DIV_MAX: natural := CLK_FREQ / SER_FREQ - 1;

	signal tx_state:    state;
	signal tx_clk_div:  integer range 0 to CLK_DIV_MAX;
	signal tx_data_tmp: std_logic_vector(7 downto 0);
	signal tx_bit_cnt:  integer range 0 to BRK_LEN;

	signal rx_state:    state;
	signal rxd_d:       std_logic_vector(3 downto 0);
	signal rx_data_i:   std_logic_vector(7 downto 0);
	signal rx_clk_div:  integer range 0 to CLK_DIV_MAX;
	signal rx_bit_cnt:  integer range 0 to BRK_LEN;

begin

	tx_proc: process(clk)
	begin
		if rising_edge(clk) then
			if reset = '1' then
				tx_state    <= idle;
				tx_clk_div  <= 0;
				tx_busy     <= '0';
				tx_end      <= '0';
				txd         <= '1';
				tx_data_tmp <= (others => '0');
				tx_bit_cnt  <= 0;

			elsif tx_state /= idle and tx_clk_div /= CLK_DIV_MAX then
				tx_clk_div <= tx_clk_div + 1;

				-- tx_end pulse coincides with last cycle of tx_busy
				if (tx_state = stop2 or (tx_state = break and tx_bit_cnt = BRK_LEN - 1))
				   and tx_clk_div = CLK_DIV_MAX - 1 then
					tx_end <= '1';
				end if;

			else	-- tx_state = idle (ready to transmit), or at the end of a bit period

				-- defaults
				tx_clk_div <= 0;
				tx_end     <= '0';

				case tx_state is
				when idle =>
					if tx_req = '1' then
						-- send start bit
						tx_busy     <= '1';
						txd         <= '0';
						tx_data_tmp <= tx_data;
						tx_state    <= data;
						tx_bit_cnt  <= 0;
					elsif tx_brk = '1' then
						tx_busy     <= '1';
						txd         <= '0';
						tx_state    <= break;
						tx_bit_cnt  <= 0;
					else
						txd         <= '1';
					end if;

				when data =>
					txd <= tx_data_tmp(0);

					if tx_bit_cnt = 7 then
						tx_state    <= stop1;
					else
						tx_data_tmp <= '0' & tx_data_tmp(7 downto 1);
						tx_bit_cnt  <= tx_bit_cnt + 1;
					end if;

				when stop1 =>
					txd      <= '1';
					tx_state <= stop2;

				when stop2 =>
					txd      <= '1';
					tx_state <= idle;
					tx_busy  <= '0';

				when break =>
					txd <= '0';

					if tx_bit_cnt = BRK_LEN - 1 then
						tx_state <= idle;
						txd      <= '1';
						tx_busy  <= '0';
					else
						tx_bit_cnt <= tx_bit_cnt + 1;
					end if;

				when others =>
					tx_state <= idle;

				end case;
			end if;
		end if;
	end process;


	rx_proc: process(clk)
	begin
		if rising_edge(clk) then
			if reset = '1' then
				rx_state      <= idle;
				rxd_d         <= (others => '1');
				rx_data_i     <= (others => '0');
				rx_data_valid <= '0';
				rx_err        <= '0';
				rx_brk        <= '0';
				rx_clk_div    <= 0;
				rx_bit_cnt    <= 0;

			else
				-- double-latching
				rxd_d <= rxd_d(2 downto 0) & rxd;

				-- defaults
				rx_data_valid <= '0';
				rx_err        <= '0';
				rx_brk        <= '0';

				case rx_state is
				when idle =>
					if rxd_d(3) = '1' and rxd_d(2) = '0' then
						rx_state   <= start;
						rx_clk_div <= 0;
					end if;

				when start =>
					-- wait half a bit period
					if rx_clk_div = CLK_DIV_MAX / 2 then
						-- rxd still low?
						if rxd_d(2) = '0' then
							rx_state   <= data;
							rx_clk_div <= 0;
							rx_bit_cnt <= 0;
							rx_data_i  <= (others => '0');
						else
							-- this was a glitch
							rx_state   <= idle;
							rx_clk_div <= 0;
						end if;
					else
						rx_clk_div <= rx_clk_div + 1;
					end if;
							
				when data =>
					-- wait a full bit period
					if rx_clk_div = CLK_DIV_MAX then
						rx_clk_div <= 0;
						rx_bit_cnt <= rx_bit_cnt + 1;
						rx_data_i  <= rxd_d(2) & rx_data_i(7 downto 1);

						if rx_bit_cnt = 7 then
							rx_state <= stop1;
						end if;
					else
						rx_clk_div <= rx_clk_div + 1;
					end if;

				when stop1 =>
					-- wait a full bit period
					if rx_clk_div = CLK_DIV_MAX then
						rx_clk_div <= 0;
						rx_bit_cnt <= rx_bit_cnt + 1;

						if rxd_d(2) = '1' then
							-- valid word received
							rx_state      <= idle;
							rx_data_valid <= '1';

						elsif rx_data_i /= x"00" then
							-- non-zero bits received but no stop bit -> framing error
							rx_state <= idle;
							rx_err   <= '1';

						else
							-- all zeros received, start of break?
							rx_state   <= break;

						end if;
					else
						rx_clk_div <= rx_clk_div + 1;
					end if;

				when break =>
					if rx_bit_cnt = BRK_LEN - 1 then
						-- proper break received
						rx_state <= idle;
						rx_brk   <= '1';

					elsif rxd_d(2) = '1' then
						-- now we start checking every sample
						rx_state <= idle;
						rx_err   <= '1';

					elsif rx_clk_div = CLK_DIV_MAX then
						rx_clk_div <= 0;
						rx_bit_cnt <= rx_bit_cnt + 1;

					else
						rx_clk_div <= rx_clk_div + 1;
					end if;
					
				when others =>
					rx_state <= idle;

				end case;
			end if;
		end if;
	end process;

	rx_data <= rx_data_i;

end;
