/* Copyright bosc
 * author: zhaohong
 * Function: receive active setipnum, and map the interrupt file ,last,delivery the irqs*/
module imsic_csr_reg #(
parameter NR_INTP_FILES         = 7,      // m,s,5vs,
parameter XLEN                  = 64,     // m,s,5vs,for RV32,32,for RV64,64
parameter NR_SRC_WIDTH          = 8, //max is 12.
parameter NR_REG                = 1, // total number of active eips/eies registers. 
parameter NR_REG_WIDTH          = 1, // total number of active eips/eies registers. 
parameter INTP_FILE_WIDTH       = 1  //max is $clog2(65) =7bit.
)
(
//  crg
input                                               clk	                                    ,
input                                               rstn                                    , 
//imsic_csr_gate 
input       [11    :0]                              csr_addr  	                            ,
input                                               csr_rd                                  ,
input       [INTP_FILE_WIDTH-1:0]                   intp_file_sel                           ,
input                                               priv_is_illegal                         ,
input       [XLEN-1:0]                              eip_final[((NR_INTP_FILES*NR_REG)-1):0] ,
output reg  [XLEN-1:0]                              eip_sw[((NR_INTP_FILES*NR_REG)-1):0]    ,
output reg  [((NR_INTP_FILES*NR_REG)-1) :0 ]        eip_sw_wr                               ,
output reg  [31:0]                                  xtopei[NR_INTP_FILES-1:0]               ,
//top
input                                               i_csr_wdata_vld                         ,    
input                                               i_csr_v	                                ,
input       [XLEN-1:0]                              i_csr_wdata	                            ,
input       [1:0]                                   i_csr_wdata_op ,  //csr type. 01:csrrw,10:csrrs,11:csrrc  
output reg                                          o_csr_rdata_vld	                        ,
output reg  [XLEN-1:0]                              o_csr_rdata	                            ,
output reg                                          o_csr_illegal	                        ,
output reg  [NR_INTP_FILES-1:0]                     o_irq	                                 
);

// csr addr allocate accroding to the riscv aia spec.
localparam IPRIO0                                   = 12'h30;
localparam IPRIO15                                  = 12'h3F;
localparam EIDELIVERY_OFF                           = 12'h70;
localparam EITHRESHOLD_OFF                          = 12'h72;
localparam EIP0_OFF                                 = 12'h80;
localparam EIP63_OFF                                = 12'hBF;
localparam EIE0_OFF                                 = 12'hC0;
localparam EIE63_OFF                                = 12'hFF;
//temp parameter used inside
localparam MUX_NR_REG = ((XLEN == 32) ? NR_REG : NR_REG*2);  //diff the XLEN,to decide whether csr_addr's scope is in the required range..
localparam OFFSET_WIDTH = (XLEN == 32) ? 6 : 5; //only even addr of both eip and eie is used when xlen is 64.
localparam CURR_ADDR_WIDTH = ((INTP_FILE_WIDTH + NR_REG_WIDTH) > OFFSET_WIDTH) ? (INTP_FILE_WIDTH + NR_REG_WIDTH+1) : (OFFSET_WIDTH + 1);

/** Interrupt files registers */
reg         [NR_INTP_FILES-1:0]                     eidelivery                          ;// NR_INTP_FILES altogether, 1bit each file.
reg         [XLEN-1:0]                              eithreshold[(NR_INTP_FILES-1):0]    ;// XLEN bit each file
reg         [XLEN-1:0]                              eie[((NR_INTP_FILES*NR_REG)-1):0]   ;
reg                                                 csr_wr_illegal                      ;
reg                                                 csr_rd_illegal                      ;
reg         [NR_INTP_FILES-1:0]                     irq_min_st                          ;// NR_INTP_FILES altogether, 1bit each file.
reg         [NR_INTP_FILES-1:0]                     irq_out                             ;// NR_INTP_FILES altogether, 1bit each file.
reg         [31:0]                                  xtopei_out[NR_INTP_FILES-1:0]       ;
reg         [NR_SRC_WIDTH-1:0]                      irq_id                              ;

wire        [INTP_FILE_WIDTH + NR_REG_WIDTH -1:0]   curr_intf_base_addr                 ;
wire        [CURR_ADDR_WIDTH-1 :0]                  curr_intf_addr                      ;
wire        [OFFSET_WIDTH   -1 :0]                  mux_csr_addr                        ;
wire                                                csr_wdata_vld                       ;
reg         [XLEN-1:0]                              csr_wdata_mux                       ;
reg         [XLEN-1:0]                              wdata_mux                           ;
//some temp signals for recognize on illegal access when XLEN is 64.
assign curr_intf_base_addr                          = intp_file_sel*NR_REG              ;
assign mux_csr_addr                                 = (XLEN == 32) ? csr_addr[5:0] : csr_addr[5:1];
assign curr_intf_addr[CURR_ADDR_WIDTH-1:0]          = curr_intf_base_addr + mux_csr_addr      ; //*64 max is 13bit.
assign o_csr_illegal    = csr_wr_illegal | csr_rd_illegal;
assign csr_wdata_vld = i_csr_wdata_vld & csr_rd;
always @(*)begin
    if (csr_wdata_vld) begin
        casez (csr_addr) 
            EIDELIVERY_OFF: begin
                wdata_mux[XLEN-1:0] = eidelivery[intp_file_sel];
            end
            EITHRESHOLD_OFF:begin
                wdata_mux[XLEN-1:0] = eithreshold[intp_file_sel];
            end
            12'b0000_10??_????:begin
                wdata_mux[XLEN-1:0] = eip_sw[curr_intf_addr];
            end
            12'b0000_11??_????:begin
                wdata_mux[XLEN-1:0] = eie[curr_intf_addr];
            end
            default :
                wdata_mux[XLEN-1:0] = i_csr_wdata;
        endcase
    end
    else
        wdata_mux[XLEN-1:0] = i_csr_wdata;
end
always @(*)begin
    if (csr_wdata_vld) begin
        case(i_csr_wdata_op)
            2'b10: // SET
                csr_wdata_mux[XLEN-1:0] = i_csr_wdata | wdata_mux;
            2'b11: // CLR
                csr_wdata_mux[XLEN-1:0] = (~i_csr_wdata) & wdata_mux ;
            default : // RW or non-illegal
                csr_wdata_mux[XLEN-1:0] = i_csr_wdata;
        endcase
    end 
    else
        csr_wdata_mux[XLEN-1:0] = i_csr_wdata;
end
// 
integer s,t;
always @(posedge clk or negedge rstn)
begin
    if (~rstn)begin 
        eidelivery          <=  {NR_INTP_FILES{1'b0}}; 
        csr_wr_illegal      <=  1'b0; 
        for (s = 0; s < NR_INTP_FILES; s++) begin
            eithreshold[s]  <=  {(XLEN){1'b0}}; 
            for(t=0; t< NR_REG;t++) begin
                eip_sw[s*NR_REG +t]     <=  {XLEN{1'b0}}; 
                eie[s*NR_REG+t]         <=  {XLEN{1'b0}}; 
                eip_sw_wr[s*NR_REG+t]   <=  1'b0; 
            end
        end
    end
    /** IMSIC channel handler for interrupt file CSRs */
    else if (csr_wdata_vld) begin
        if (priv_is_illegal | (i_csr_wdata_op == 2'b00))
            csr_wr_illegal <=  1'b1;    
        else begin
            casez (csr_addr) 
                12'b0000_0011_????:begin
                    if(i_csr_v == 1'b1)         // virtual mode: it is inaccessiable region.
                        csr_wr_illegal   <=  1'b1;
                    else begin
                        if(XLEN == 64) begin
                            if (csr_addr[0] == 1'b1)
                                csr_wr_illegal <=  1'b1;    //only even number can be accessed.
                        end
                    end
                end
                EIDELIVERY_OFF: begin
                    eidelivery[intp_file_sel] <= csr_wdata_mux[0];
                end
                EITHRESHOLD_OFF:begin
                    eithreshold[intp_file_sel] <= csr_wdata_mux[XLEN-1:0];
                end
                12'b0000_10??_????:begin
                    if(csr_addr[5:0]< MUX_NR_REG) begin
                        if(XLEN == 32)begin
                            eip_sw[curr_intf_addr] <= (|curr_intf_addr) ? csr_wdata_mux[XLEN-1:0] : {csr_wdata_mux[XLEN-1:1],1'b0}; // interrupt 0 is invalid.
                            eip_sw_wr[curr_intf_addr] <= 1'b1;
                        end
                        else if (csr_addr[0] == 1'b1)
                            csr_wr_illegal <= 1'b1;                                       
                        else begin
                            eip_sw[curr_intf_addr] <= (|csr_addr[5:0]) ? csr_wdata_mux[XLEN-1:0] : {csr_wdata_mux[XLEN-1:1],1'b0};
                            eip_sw_wr[curr_intf_addr] <= 1'b1;
                        end  
                    end
                    else
                        csr_wr_illegal <= 1'b1;                                       
                end
                12'b0000_11??_????:begin
                    if(csr_addr[5:0]< MUX_NR_REG) begin
                        if(XLEN == 32)
                            eie[curr_intf_addr] <= csr_wdata_mux[XLEN-1:0];
                        else if (csr_addr[0] == 1'b1)
                            csr_wr_illegal <= 1'b1;                                       
                        else 
                            eie[curr_intf_addr] <= csr_wdata_mux[XLEN-1:0];
                    end
                    else
                        csr_wr_illegal <= 1'b1;                                       
                end
                default: csr_wr_illegal <= 1'b0;
            endcase
        end
    end
    else begin
        csr_wr_illegal <= 1'b0;
      //eidelivery          <=  eidelivery  ; 
      //eithreshold         <=  eithreshold ; 
      //eip_sw              <=  eip_sw      ; 
        eip_sw_wr           <=  {{NR_INTP_FILES * NR_REG}{1'b0}}        ; 
      //eie                 <=  eie         ; 
    end
end
always @(posedge clk or negedge rstn)
begin
    if (~rstn)begin 
        o_csr_rdata    <= {XLEN{1'b0}};
        csr_rd_illegal <= 1'b0;
    end
    else if (csr_rd) begin
        if (priv_is_illegal)
            csr_rd_illegal <=  1'b1;    
        else begin
            casez (csr_addr) 
                12'b0000_0011_????:begin
                    if(i_csr_v == 1'b1)         // virtual mode: it is inaccessiable region.
                        csr_rd_illegal   <=  1'b1;
                    else begin
                        if(XLEN == 64) begin
                            if (csr_addr[0] == 1'b1)
                                csr_rd_illegal <=  1'b1;    //only even number can be accessed.
                        end
                    end
                end
                EIDELIVERY_OFF: begin
                    o_csr_rdata     <= {{(XLEN-1){1'b0}}, eidelivery[intp_file_sel]};
                    csr_rd_illegal  <=  1'b0;    
                end
                EITHRESHOLD_OFF:begin
                    o_csr_rdata     <=  eithreshold[intp_file_sel];
                    csr_rd_illegal  <=  1'b0;    
                end
                12'b0000_10??_????:begin
                    if(csr_addr[5:0]< MUX_NR_REG) begin
                        if(XLEN == 32)
                            o_csr_rdata <= eip_final[curr_intf_addr];
                        else if (csr_addr[0] == 1'b0)
                            o_csr_rdata <= eip_final[curr_intf_addr];
                        else 
                            csr_rd_illegal <=  1'b1;                                       
                    end
                    else
                        csr_rd_illegal <= 1'b1;                                       
                end
                12'b0000_11??_????:begin
                    if(csr_addr[5:0]< MUX_NR_REG) begin
                        if(XLEN == 32)
                            o_csr_rdata <= eie[curr_intf_addr];
                        else if (csr_addr[0] == 1'b0)
                            o_csr_rdata <= eie[curr_intf_addr];
                        else 
                            csr_rd_illegal <=  1'b1;                                       
                    end
                    else
                        csr_rd_illegal <= 1'b1;                                       
                end
                default: begin 
                    csr_rd_illegal<= 1'b0;
                    o_csr_rdata   <= {XLEN{1'b0}};
                end
            endcase
        end
    end
    else begin
        o_csr_rdata    <= o_csr_rdata;
        csr_rd_illegal  <=  1'b0;                                       
    end
end
//code on gen of rdata_vld, the next cycle following the rd. both rdata_vld and rd are only 1cycle active.
always @(posedge clk or negedge rstn)
begin
    if (~rstn)
        o_csr_rdata_vld <= 1'b0;
    else if (csr_rd)
        o_csr_rdata_vld <= 1'b1;
    else
        o_csr_rdata_vld <= 1'b0;
end
//========== code on the delivery of irqs. =============================
integer i,j,k,n;
/** For each interrupt file look for the highest pending and enable interrupt 
k - interrupt file number,
i - reg number,
j - arrangement of interrupt number in i,
k*NR_REG - select the current interrupt file */
always @(*)begin
        for (k = 0; k < NR_INTP_FILES; k++) begin
            xtopei_out[k] = 32'h0; 
            irq_out[k]= 1'b0; 
            for (i = NR_REG-1; i >= 0; i--) begin
                for (j = XLEN-1; j >= 0; j--) begin 
                    irq_id=XLEN*i+j;
                    if ((eie[(k*NR_REG)+i][j] & eip_final[(k*NR_REG)+i][j]) & 
                        ((eithreshold[k] == 0) | (irq_id < eithreshold[k]))) begin
                            xtopei_out[k][10:0]     = {{(11-NR_SRC_WIDTH){1'b0}},irq_id};  // curr  interrupt priority
                            xtopei_out[k][26:16]    = {{(11-NR_SRC_WIDTH){1'b0}},irq_id};  // curr  interrupt number.
                            irq_out[k]          = eidelivery[k];// If delivery is enable for this intp file, tell the hart 
                    end
                end
            end
        end
end 
always @(posedge clk or negedge rstn)
begin
    if (~rstn) begin
        for (n = 0; n < NR_INTP_FILES; n++) begin
            xtopei[n]  <= 32'd0;
            o_irq[n]   <= 1'b0; 
        end
    end
    else begin
        for (n = 0; n < NR_INTP_FILES; n++) begin
            xtopei[n] <= xtopei_out[n];
            o_irq[n]  <= irq_out[n] ; //select the vgein file for vs.
        end
    end
end
//always @(*)
//begin
//    o_xtopei[0]  = xtopei[0];
//    o_xtopei[1]  = xtopei[1];
//    o_xtopei[2]  = xtopei[i_csr_vgein+1];
//end
//assign o_xtopei[2:0]  = {xtopei[i_csr_vgein+1],xtopei[1:0]};
// ================================================================
endmodule
