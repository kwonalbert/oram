
This REAMDE describes the code structure for Tiny ORAM.

--------------------------------------------------------------------------------
Introduction
--------------------------------------------------------------------------------

Tiny ORAM is partitioned into a frontend and a backend as this leads to a more
modular design.  At a system level, the major components connect like this:

	User design <= Memory interface =>
	Frontend <= Position-based ORAM interface =>
	Backend <= Memory interface =>
	DRAM controller

The 'Memory interface' is:
  (op, address, data) where op = read/write;
  uses the ready/valid handshake for passing data (see below)

The 'Position-based ORAM interface' is:
  (op, address, data, currentPos, NewPos)
  where op = read/write/some additional low-level commands;
  uses the ready/valid handshake for passing data (see below)

The frontend manages the block-to-position mapping, and translates a frontend
access into one or multiple backend accesses.  A Unified frontend is currently
available, which manages the position map (PosMap) recursively [3].  The Unified
frontend hides most of the recursion overhead when the access pattern has good
locality, using a PosMap-Lookaside-Buffer (PLB).  A basic (non-recursive)
frontend is under development.

The backend is based on Path ORAM by Stefanov et. al [1]; i.e., structures
external memory as a binary tree and reads random paths in the tree to retrieve
blocks requested by the frontend.  The backend also manages the stash and evicts
blocks back to the tree.  Tiny ORAM currently supports two backend protocols.
One is the original Path ORAM in [1].  The other is RAW ORAM, a variant of
Path ORAM proposed in [2].  RAW ORAM simplifies integrity verification, and
reduces the number of encryption and hash units required.  (Note: we refer to
'RAW ORAM' as 'REW ORAM' in the code for legacy reasons.  This will be
corrected in future releases.)

Sitting between the frontend and backend is the PosMap MAC integrity verification 
unit described in [3].

*** Note: The RAW ORAM code is a little out of date and probably won't compile.  
	The issues are minor: it would be great if someone could fix them! ***

--------------------------------------------------------------------------------
Code structure
--------------------------------------------------------------------------------

Tiny ORAM								(TinyORAMCore.v, top module)
	Frontend 							(choose between Basic or Unified, frontend/Frontend.v)
		Basic frontend					(under development)
		-or- Unified frontend			(frontend/UORAMController.v)
			PosMap+PLB					(frontend/PosMapPLB.v)
			DataPath					(frontend/UORAMDataPath.v)
		Integrity Verifier				(integrity/IntegrityVerifier.v)
	Backend								(choose between Path ORAM or RAW ORAM, backend/PathORAMBackend.v)
		Control logic					(backend/PathORAMBackendCore.v)
			Address Generator			(addr/*.v)
			Stash						(stash/*.v)
		Path ORAM Backend 				(backend/AESPathORAM.v)
			Symmetric Encryption		(encryption/basic/*.v)
		-or- RAW ORAM Backend 			(backend/AESREWORAM.v)
			Symmetric Encryption		(encryption/rew/*.v)

Data flows (roughly) top to bottom.  That is, a user request passes through 
frontend -> integrity verifier -> backend control logic/stash -> encryption 
units, and vice versa.
			
--------------------------------------------------------------------------------
FAQ: Where do I set ORAM parameters?
--------------------------------------------------------------------------------
	
All parameters (block size, Z, Path vs. RAW ORAM, etc) are set in 
./include/PathORAM.vh.  If you instantiate TinyORAMCore.v	and don't override 
parameters, they will come from that include file.

--------------------------------------------------------------------------------
FAQ: How do I set the macros?
--------------------------------------------------------------------------------
	
Here is the guide:	
	
set MACROSAFE=1 	always.

set SIMULATION=1 	for any simulation.  Most FPGA tools are smart enough to 
					ignore this for synthesis so you can probably just leave it 
					set always.
					
SIMULATION_VIVADO=1 for any Xilinx Vivado simulation.  That tool has some quirks 
					(we devved on version 2013.4).
					
set FPGA_MEMORY=1 	if you are devving on an FPGA.  Leave unset if you are 
					targeting an ASIC (see ../ASIC/* for relevant code).

--------------------------------------------------------------------------------
FAQ: Where are there examples of TinyORAMCore instantiated?
--------------------------------------------------------------------------------
	
TinyORAMASICWrap.v: 
	A test harness for Tiny ORAM that we developed for the ASIC tapeout.  This 
	bundles the ORAM core and a traffic generator (acts as a user that sends 
	requests).  Set Mode_DummyGen = 0. 	
	
frontend/test/testUORAM.v: 
	Instantiates TinyORAMASICWrap in a simulator-level testbench.  This is a 
	good bare-bones way to test the code.  Includes a simulator-level DRAM 
	controller.
		
../boards/vc707/TinyORAMTop_vc707.v:
	A valid top file for the VC707/KC705 Xilinx FPGA boards.  Instantiates Tiny 
	ORAM, traffic generator, and a way to collect results and send requests from 
	a user machine (e.g., laptop) over UART.  This module is a little out of 
	date but should be easy to get working again.
		
--------------------------------------------------------------------------------
FAQ: Ready/Valid handshake: how do modules communicate?
--------------------------------------------------------------------------------
		
Most modules use a "latency insensitive" (basically a FIFO) interface to 
communicate with their neighbours.  Suppose module A wishes to send data to 
module B.  If they use Ready/Valid, they will have the following interface:	
		
Module A:
	OutData		Output
	OutValid	Output
	OutReady	Input
		
Module B:
	InData		Input, connected to Module A OutData
	InValid		Input, connected to Module A OutValid
	InReady		Output, connected to Module A OutReady
	
Semantically, Module A will bring OutValid high when it has data to send (same 
as FIFO.Empty == false).  Module B will bring InReady high when it can accept 
data (i.e., FIFO.full == false).  When both signals are high in the same cycle, 
data is transferred on the bus.

--------------------------------------------------------------------------------
FAQ: What are the JTAG_ signals in these modules?
--------------------------------------------------------------------------------	
	
We added these for debugging during our ASIC tapeout.  They can be left undriven.
	
--------------------------------------------------------------------------------
FAQ: What do you use for crypto?
--------------------------------------------------------------------------------	
	
Tiny ORAM uses AES for encryption and SHA3 for integrity verification.  We use 
Rudolf Usselmann's non-pipelined AES for generating pseudo-random numbers and 
Homer Hsing's tinyaes core for the main ORAM path encrypt/decrypt operations.  
We also use Homer's SHA3 core for integrity verification.  We got these projects 
from Open Cores.

We have extended these modules slightly for our purposes and therefore include 
the code.

Thanks to Rudolf and Homer for the awesome work!!
	
--------------------------------------------------------------------------------
Conventions
--------------------------------------------------------------------------------

- 	All Verilog files (*.v and *.vh) assume tab = 4 spaces.

- 	Files with a suffix 'Testbench' are RTL testbenches.  These are found in
	/test subdirectories below each major code branch (e.g., ./frontend/test).
	Refer to each testbench for its usage, but (READ) be aware that most of
	these testbenches are _out of data_ and no longer maintained.  To test Tiny
	ORAM, refer to ../tests/README.txt.

-	Files named 'TinyORAMTop' are FPGA top files.  That is, they contain FPGA
	pinouts and can be used to generate an FPGA bitstream.  Some examples are
	given in ../boards.

-	Files with the extension *.vh are include files.  If an include file has the
	suffix 'Local', it contains only derived constants/localparams -- i.e., you
	shouldn't modify it unless you know what you are doing.

--------------------------------------------------------------------------------
Citations
--------------------------------------------------------------------------------

[1] Emil Stefanov, Marten van Dijk, Elaine Shi, Christopher Fletcher, Ling Ren,
	Xiangyao Yu, and Srinivas Devadas. 2013.
	Path ORAM: an extremely simple oblivious RAM protocol.
	In Proceedings of CCS'13.

[2] Christopher W. Fletcher, Ling Ren, Albert Kwon, Marten van Dijk, 
	Emil Stefanov, Dimitrios Serpanos, Srinivas Devadas. 2015.
	A Low-Latency, Low-Area Hardware Oblivious RAM Controller
	In Proceedings of FCCM'15.
	
[3]	Christopher W. Fletcher, Ling Ren, Albert Kwon, Marten van Dijk, 
	Srinivas Devadas. 2015.
	Freecursive ORAM: [Nearly] Free Recursion and Integrity Verification for 
	Position-based Oblivious RAM.
	In Proceedings of ASPLOS'15.
	