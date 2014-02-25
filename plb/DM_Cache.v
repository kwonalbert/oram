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
 
    output reg OutValid,
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
    reg [LogLineSize-1:0] RefillCounter;
    reg WriteReg;
    wire RefillStart, Refilling, RefillFinish;
    
    assign RefillStart = Enable && Ready && (Cmd == CacheRefill);
    assign RefillFinish = (Cmd_reg == CacheRefill) && (RefillCounter == RefillLatency - 1);
    assign Refilling = RefillStart || (Cmd_reg == CacheRefill && RefillCounter != 0);
    
    reg  TagInit;
    assign Ready = RefillCounter == 0 && !WriteReg && !TagInit;
    
    // control signals for data and tag arrays
    wire DataEnable, TagEnable, DataWrite, TagWrite;
    
    assign DataEnable = Enable || (WriteReg && Hit);
    assign DataWrite = DataEnable && (WriteReg || Refilling);
    assign TagEnable = TagInit || (Enable && (Ready || RefillFinish));
    assign TagWrite = TagInit || (TagEnable && RefillFinish);
    
    // addresses for data and tag arrays
    reg  [AddrWidth-1:0] Addr_reg;
    wire [AddrWidth-1:0] Addr;
    wire [TArrayAddrWidth-1:0] TArrayAddr, InitTArrayAddr; 
    wire [DArrayAddrWidth-1:0] DArrayAddr;
    wire [LogLineSize-1:0] Offset;
    
    assign Addr = Ready ? AddrIn : Addr_reg;
    assign TArrayAddr = TagInit ? InitTArrayAddr : ((Addr >> LogLineSize) % NumLines);
    assign Offset = Addr[LogLineSize-1:0] + RefillCounter;
    assign DArrayAddr = (TArrayAddr << LogLineSize) + Offset;  
    
    wire InitEnd;
    Counter #(.Width(TArrayAddrWidth))
        TagInitCounter (Clock, Reset, 1'b0, 1'b0, TagInit, {TArrayAddrWidth{1'bx}}, InitTArrayAddr); // load = set = 0, in= x      
    CountCompare #(.Width(TArrayAddrWidth), .Compare((1 << TArrayAddrWidth) - 1))
        PosMapInitCountCmp(InitTArrayAddr, InitEnd);
    
    // IO for data and tag arrays
    reg [DataWidth-1:0] DIn_reg;
    reg [ExtraTagWidth-1:0] ExtraTagReg;
    wire [DataWidth-1:0] DataIn;
    wire [TagWidth+ExtraTagWidth:0] TagIn, TagOut;
    
    assign TagIn = TagInit ? {1'b0, {TagWidth+ExtraTagWidth{1'bx}}} : {1'b1, ExtraTagReg, Addr[AddrWidth-1:LogLineSize]};
    assign DataIn = WriteReg ? DIn_reg : DIn;

    // data and tag array
    RAM #(.DWidth(DataWidth), .AWidth(DArrayAddrWidth)) 
        DataArray(Clock, Reset, DataEnable, DataWrite, DArrayAddr, DataIn, DOut);

    RAM #(.DWidth(TagWidth+1+ExtraTagWidth), .AWidth(TArrayAddrWidth)) 
        TagArray(Clock, Reset, TagEnable, TagWrite, TArrayAddr, TagIn, TagOut);  
 
    // output for cache outcome
    wire LineValid;
    reg  RefillReg;
    assign LineValid = TagOut[TagWidth+ExtraTagWidth];

    assign Hit = (Cmd_reg == CacheWrite || Cmd_reg == CacheRead) 
                    && Addr_reg[AddrWidth-1:LogLineSize] == TagOut[TagWidth-1:0] && LineValid;  // valid && tag match
    assign Evicting = RefillReg && LineValid; // a valid line is there. danger: on refillFinish, cannot use new tag!
    assign AddrOut = TagOut[TagWidth-1:0] << LogLineSize;
    assign ExtraTagOut = TagOut[TagWidth+ExtraTagWidth-1:TagWidth];
        
    always@(posedge Clock) begin
        if (Reset) begin
            RefillCounter <= 0;
            Cmd_reg <= CacheRead;
            WriteReg <= 0;
            OutValid <= 0;
            TagInit <= 1;  
        end
        else if (TagInit) begin
            TagInit <= !InitEnd;
        end
        
        else begin 
            if (Ready && Enable) begin
                Cmd_reg <= Cmd;
                Addr_reg = AddrIn;
                DIn_reg <= DIn;
                ExtraTagReg <= ExtraTagIn;
                
                if (Cmd == CacheRefill && Offset != 0) begin
                    $display("Must provide an aligned address for refilling.");                       
                    $finish;
                end       
            end
            
            if (Refilling & Enable) begin
                RefillCounter <= RefillCounter + 1;
            end
            
            WriteReg <= Enable && Ready && (Cmd == CacheWrite);
            RefillReg <= Enable && Refilling;
            OutValid <= Enable && Ready;
        end
    end

endmodule
