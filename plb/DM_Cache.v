`include "Const.vh"

module DM_Cache
#(parameter DataWidth = 32, LogLineSize = 4, Capacity = 32768, AddrWidth = 32, ExtraTagWidth = 32)
(
    input Clock, Reset,
    output Ready,
    input Enable,
    input [1:0] Cmd,        // 00 for write, 01 for read, 10 for refill, 11 for remove
    input [AddrWidth-1:0] AddrIn,
    input [DataWidth-1:0] DIn,
    input [ExtraTagWidth-1:0] ExtraTagIn,
 
    output Valid,
    output Hit,   
    output [DataWidth-1:0] DOut,
    output Evicting,
    output [AddrWidth-1:0] AddrOut,
    output [ExtraTagWidth-1:0] ExtraTagOut
);
 
    `include "CacheLocal.vh";
    `include "CacheCmdLocal.vh";
 
    // Cmd related states
    reg [1:0] Cmd_reg;
    reg [LogLineSize:0] CmdCounter;
    wire WriteFinish, RefillStart, Refilling, RefillFinish;
    
    assign RefillStart = Enable && Ready && (Cmd == CacheRefill);
    assign WriteFinish = (Cmd_reg == CacheWrite) && (CmdCounter == WriteLatency);
    assign RefillFinish = (Cmd_reg == CacheRefill) && (CmdCounter == RefillLatency);
    assign Writing = (Cmd_reg == CacheWrite) && Hit && (CmdCounter <= WriteLatency);
    assign Refilling = (Cmd_reg == CacheRefill) && (CmdCounter < RefillLatency);
    assign Ready = (!Writing) && (!Refilling && !RefillFinish);
    
    // control signals for data and tag arrays
    wire DataEnable, TagEnable, DataWrite, TagWrite;
    
    assign DataEnable = Enable || (WriteFinish && Hit);
    assign DataWrite = DataEnable && (Writing || RefillStart || Refilling);
    assign TagEnable = (Enable && Ready) || RefillFinish;
    assign TagWrite = TagEnable && RefillFinish;
    
    // addresses for data and tag arrays
    reg [AddrWidth-1:0] Addr_reg;
    wire [AddrWidth-1:0] Addr;
    wire [TArrayAddrWidth-1:0] TArrayAddr;   
    wire [DArrayAddrWidth-1:0] DArrayAddr;
    wire [LogLineSize-1:0] Offset;
    
    assign Addr = Ready ? AddrIn : Addr_reg;
    assign TArrayAddr = (Addr >> LogLineSize) % NumLines;
    assign Offset = Addr[LogLineSize-1:0];
    assign DArrayAddr = (TArrayAddr << LogLineSize) + Offset + (Refilling ? CmdCounter : 0);  
    
    // IO for data and tag arrays
    reg [DataWidth-1:0] DIn_reg;
    reg [ExtraTagWidth-1:0] ExtraTagReg;
    wire [DataWidth-1:0] DataIn;
    wire [TagWidth+ExtraTagWidth:0] TagIn, TagOut;
    
    assign TagIn = {1, ExtraTagReg, Addr[AddrWidth-1:LogLineSize]};
    assign DataIn = Writing ? DIn_reg : DIn;

    // data and tag array
    RAM #(.DWidth(DataWidth), .AWidth(DArrayAddrWidth)) 
        DataArray(Clock, Reset, DataEnable, DataWrite, DArrayAddr, DataIn, DOut);
    RAM #(.DWidth(TagWidth+1+ExtraTagWidth), .AWidth(TArrayAddrWidth),
        .EnableInitial(1), .Initial(  {(1 << TArrayAddrWidth) * ((TagWidth+ExtraTagWidth)+1) {1'b0} } )) 
        TagArray(Clock, Reset, TagEnable, TagWrite, TArrayAddr, TagIn, TagOut);  
    
   // {(1 << TArrayAddrWidth){0, {(TagWidth+ExtraTagWidth){1'bx}}}}
    
    // output for cache outcome
    reg EnableReg, ValidReg;             // hack: assuming all latency = 1
    assign Valid = ValidReg; 
    assign Hit = (Cmd_reg == CacheWrite || Cmd_reg == CacheRead) 
                    && Addr_reg[AddrWidth-1:LogLineSize] == TagOut[TagWidth-1:0] && TagOut[TagWidth+ExtraTagWidth];  // valid && tag match
    assign Evicting = EnableReg && (Cmd_reg == CacheRefill) && TagOut[TagWidth+ExtraTagWidth] && (Refilling || RefillFinish); // a valid line is there
    assign AddrOut = TagOut[TagWidth-1:0] << LogLineSize;
    assign ExtraTagOut = TagOut[TagWidth+ExtraTagWidth-1:TagWidth];
    
    initial begin
        EnableReg <= 0;
        ValidReg <= 0;
        CmdCounter <= -1;
    end
        
    always@(posedge Clock) begin
        if (Reset) begin
            EnableReg <= 0;
            ValidReg <= 0;
            CmdCounter <= -1;
        end
        else if (Ready && Enable) begin
            Cmd_reg <= Cmd;
            Addr_reg <= AddrIn;
            DIn_reg <= DIn;
            ExtraTagReg <= ExtraTagIn;
            
            // check that an aligned address is provided for refilling
            if (Cmd == CacheRefill && Offset != 0) begin                         
                $finish;
            end
            
            if (Cmd == CacheWrite || Cmd == CacheRefill) begin
                CmdCounter <= 1;         
            end          
        end
        
        else if (WriteFinish || RefillFinish) begin // this must come first, because '*Finish' counts as '*ing'
            CmdCounter <= -1;
        end 
        else if ((Writing || Refilling) && Enable) begin
            CmdCounter <= CmdCounter + 1;
        end
                
        EnableReg <= Enable;
        ValidReg <= Enable && Ready;
    end

endmodule