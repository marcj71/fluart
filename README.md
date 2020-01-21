# fluart -- the featureless UART

A [UART](https://en.wikipedia.org/wiki/Universal_asynchronous_receiver-transmitter) (Universal Asynchronous Receiver/Transmitter) provides a [serial interface](https://en.wikipedia.org/wiki/Serial_port), typically implementing the RS-232 protocol. Many VHDL UART models replicate the functionality of the well-known 8250/16x50 line of UARTs. When used in modern embedded systems, these UARTs can be overly complex for the purpose. This UART only provides the basic functions and is therefore called _the featureless UART_ or <tt>fluart</tt>. Look at all the features it **doesn't** have:

No inscrutable baud rate generator
: Most UARTs run at a clock frequency that is determined by the system clock frequency, the supported baud rate(s) and the amount of oversampling. In many cases, the user must precalculate divisors and set these values in several registers, hoping to come close to the actual baud rate. The <tt>fluart</tt> does the work for you during synthesis.

No oversampling
: Serial ports that are connected to long signal lines will need to handle line noise and non-standard signal levels. They sample the signal multiple times per bit period and use majority voting to decide whether the bit was high or low. Some may even infer the baud rate based on the timing of the edges.
In embedded systems, the designer is usually in full control of the data path. Noise, voltage levels and timing present no problems when modern signal integrity techniques are used.

No parity support
: The RS-232 standard allows for a parity bit that can be added to each data transfer. Again, when the signal does not suffer from the deterioration caused by a long telephone line, parity only adds overhead. Most computing systems do not handle parity errors gracefully anyway.

No FIFO
: If the processing system after the UART cannot focus its attention on an incoming byte quickly enough, it may be overwritten by the next one. Some UARTs, notably the 16550, add a FIFO (first-in, first-out) buffer to store several bytes and decrease the interrupt load. The <tt>fluart</tt> does not have a FIFO. If you need one, you can add one yourself.

No modem control lines
: Many traditional serial ports are intended for connection to a [modem](https://en.wikipedia.org/wiki/Modem). Modems usually have a number of separate wires for control and status signaling. Hardware flow control (handshaking) is part of this.
Embedded systems often have no provision or use for control lines, expecting the interface to be up and running at all times. The <tt>fluart</tt> does not have any logic for RTS/CTS/DTR/RI etc.

No processor interface (PLB/AMBA/Wishbone)
: The <tt>fluart</tt> was designed with the simplest interface possible. It does not have any support for microcontroller/microprocessor bus structures. You can add a wrapper for your preferred architecture.

## What's left?
The <tt>fluart</tt> samples the data once per bit period and deserializes it into bytes. Clocking is simple: typical FPGAs run at a clock frequency that is much higher than the serial data rate. You only supply the clock frequency and the bit rate as generics, since it's the ratio that counts. The smallest allowable ratio is 2:1, meaning that the bit rate can be at most half of the <tt>fluart</tt> clock frequency. There is no upper limit to this ratio.

All transfers are 8N1, meaning eight data bits, no parity, one stop bit.

The transmit and receive sections are completely separate and independent. If you only need one channel, the other one will be removed during synthesis ('optimized away').

The model and the testbench are written in standard VHDL93.

And yet... the <tt>fluart</tt> does have a few features. If you feel cheated, you could call it the *fast & light UART* if you want to.

Line break detection & generation
: Even though no out-of-band signals are present, it can be very useful to have at least one way to get the system's attention. Sending a [break](https://en.wikipedia.org/wiki/Universal_asynchronous_receiver-transmitter#Break_condition) is an easy way to reset or synchronize (part of) a system. Breaks are supported by most processors and APIs. The duration of the break is configurable.

Framing error detection
: When checking for a break, one gets frame error checking almost for free. This function checks that the stop bit is actually there. If not, the entire frame was likely invalid.


## Interface

```vhdl
generic (
	CLK_FREQ:	integer := 50_000_000;
	SER_FREQ:	integer := 115200;
	BRK_LEN:	integer := 10
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
```

<tt>CLK_FREQ</tt> and <tt>SER_FREQ</tt>
: The system clock frequency and desired bit rate, respectively. Only the ratio between them is used. When the ratio is low, make sure that the bit rate is within specification for the connected system.

<tt>BRK_LEN</tt>
: The duration of a break pulse, in terms of bit periods. A break generated by the <tt>fluart</tt> will be this long. A break received by the <tt>fluart</tt> must be at least this long before it is reported. This value should never be less than 10, since a normal transfer takes 10 bit periods (start bit, eight data bits, stop bit).

<tt>clk</tt> and <tt>reset</tt>
: The system clock and reset. The <tt>fluart</tt> is a fully synchronous design, acting on the rising edge of the clock input. Reset is synchronous as well and is active high.

<tt>rxd</tt> and <tt>txd</tt>
: The two-wire serial interface. <tt>rxd</tt> is the only asynchronous input to the module. It is double-latched to prevent metastability.

<tt>tx_data</tt>, <tt>tx_req</tt>, <tt>tx_busy</tt> and <tt>tx_end</tt>
: Set <tt>tx_req</tt> high for one clock cycle to transmit <tt>tx_data</tt>. The byte to be transmitted is latched in the <tt>fluart</tt>, so it must be stable only when <tt>tx_req</tt> is high. <tt>tx_busy</tt> will be high while the transfer is in progress. For convenience, <tt>tx_end</tt> will be high during the final clock cycle of the transmission (the falling edges of <tt>tx_busy</tt> and <tt>tx_end</tt> coincide).

<tt>tx_brk</tt>
: Set <tt>tx_brk</tt> high for one clock cycle to transmit a break pulse: <tt>txd</tt> will be low for <tt>BRK_LEN</tt> bit periods. <tt>tx_busy</tt> and <tt>tx_end</tt> behave just as for a normal data transfer.

<tt>rx_data</tt> and <tt>rx_data_valid</tt>
: Upon reception of a valid word (i.e., start bit low and stop bit high), <tt>rx_data_valid</tt> will be high for one clock cycle and the data will be on <tt>rx_data</tt>.

<tt>rx_brk</tt> and <tt>rx_err</tt>
: If all received data bits are low and the stop bit is low as well, the break detector is activated. When <tt>BRK_LEN</tt> low bits have passed, <tt>rx_brk</tt> will be high for one clock cycle.
If not all data bits were low, but the stop bit was low, or if a low pulse on <tt>rxd</tt> did not last at least <tt>BRK_LEN</tt> bit periods, <tt>rx_err</tt> will be set high for one clock cycle. The received data is available on <tt>rx_data</tt> for inspection.

## Timing accuracy
The <tt>fluart</tt> can work with very low ratios between the system clock and the serial bit rate, down to 2:1. This is because <tt>rxd</tt> is sampled in the middle of a bit period. If your application requires a low ratio, and the clock frequency is not an integer multiple of the bit rate, you should verify by simulation and measurement that the timing is acceptable.

## Simulation
A testbench is supplied in <tt>fluart_tb.vhdl</tt>. <tt>rxd</tt> and <tt>rxd</tt> are tied together. First, a single byte is transmitted & received, then a break. Use your preferred simulator. For [GHDL](http://ghdl.free.fr/), the following commands are sufficient:

```
ghdl -c fluart.vhdl fluart_tb.vhdl -r fluart_tb --vcd=fluart_tb.vcd --stop-time=2us
gtkwave fluart_tb.vcd &
```

## Simplicity
...is a goal in itself. If you have suggestions to simplify the logic and/or improve readability of the VHDL, let me know! There are too many style preferences to keep everyone happy, so please don't focus on indentation, naming etcetera. Live and let live.
