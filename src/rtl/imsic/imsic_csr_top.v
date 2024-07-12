/* Copyright bosc
 * author: zhaohong
 * Function: receive active setipnum, and map the interrupt file ,last,delivery the irqs*/
module imsic_csr_top #(
parameter GEILEN            = 5,    // m,s,5vs,
parameter NR_INTP_FILES     = 2+GEILEN,    // m,s,5vs,
parameter NR_HARTS          = 1 ,   //harts number,modify from 64 to 1, in 20240528.
parameter XLEN              = 64,   // 32 for RV31, 63 for RV63
parameter NR_SRC            = 256,
parameter EID_VLD_DLY_NUM   = 0, // cycles that seteip_num_vld can be delayed before used. for timing.
// DO NOT INSTANCE BY PARAMETER
localparam NR_SRC_WIDTH      = $clog2(NR_SRC) , //max is 12.
localparam NR_HARTS_WIDTH    = (NR_HARTS ==1) ? 1 : $clog2(NR_HARTS),             //6
localparam INTP_FILE_WIDTH   = $clog2(NR_INTP_FILES), // 3
localparam MSI_INFO_WIDTH    = NR_HARTS_WIDTH + INTP_FILE_WIDTH + NR_SRC_WIDTH   //17bit

)
(
//  crg
input                                       csr_clk        ,    
input                                       csr_rst        ,  //active high. port name not changed,to be no effects on integration 2024.05.10
//                                                         ,
input       [MSI_INFO_WIDTH-1:0]            i_msi_info     , 
input                                       i_msi_info_vld ,   // m,s,5vs,4harts.0-3:hart0-hart3 m file. 4-9:hart0 s+vs file.
input       [NR_HARTS_WIDTH-1:0]            hart_id        , // start from 0.
input                                       i_csr_addr_vld ,   
input       [11    :0]                      i_csr_addr     ,   
input       [1:0]                           i_csr_priv_lvl ,   
input                                       i_csr_v        ,    
input       [5:0]                           i_csr_vgein    ,    // the value must be in the range 0~NR_INTP_FILES -2.
input       [2:0]                           i_csr_claim    ,     
input       [XLEN-1:0]                      i_csr_wdata    ,    
input       [1:0]                           i_csr_wdata_op ,  //csr type. 01:csrrw,10:csrrs,11:csrrc  
input                                       i_csr_wdata_vld,    
output wire                                 o_csr_rdata_vld,    
output wire [XLEN-1:0]                      o_csr_rdata    ,    
output wire                                 o_csr_illegal  ,  
output wire [NR_INTP_FILES-1:0]             o_irq          ,  
output wire [31:0]                          o_mtopei       ,     
output wire [31:0]                          o_stopei       ,     
output wire [31:0]                          o_vstopei            
);


// DO NOT EDIT BY PARAMETER
localparam NR_REG                = (NR_SRC%XLEN == 0) ? (NR_SRC/XLEN) : (NR_SRC/XLEN+1); // total number of active eips/eies registers. 
localparam NR_REG_WIDTH          = $clog2(NR_REG);

wire        [INTP_FILE_WIDTH-1:0]                   intp_file_sel                           ;
wire                                                priv_is_illegal                         ;
wire        [XLEN-1:0]                              eip_final[((NR_INTP_FILES*NR_REG)-1):0] ;
wire        [XLEN-1:0]                              eip_sw[((NR_INTP_FILES*NR_REG)-1):0]    ;
wire        [((NR_INTP_FILES*NR_REG)-1) :0 ]        eip_sw_wr                               ;
wire        [31:0]                                  xtopei[NR_INTP_FILES-1:0]               ;
wire                                                csr_rstn_low                            ;
wire                                                vgein_legal                             ;
assign o_mtopei        = xtopei[0]      ;
assign o_stopei        = xtopei[1]      ;
assign o_vstopei       = vgein_legal ? xtopei[i_csr_vgein +1] : 32'h0;
//fix issue about reset from core,which is active high. 2024.05.10.
assign csr_rstn_low    = ~csr_rst ;

imsic_csr_reg #(
.NR_INTP_FILES    (NR_INTP_FILES    ),  
.XLEN             (XLEN             ),  
.NR_SRC_WIDTH     (NR_SRC_WIDTH   ),    
.NR_REG           (NR_REG           ),  
.NR_REG_WIDTH     (NR_REG_WIDTH     ),  
.INTP_FILE_WIDTH  (INTP_FILE_WIDTH  ) 
)
u_imsic_csr_reg
(
.clk                           (csr_clk                                        ),
.rstn                          (csr_rstn_low                                   ), 
.csr_addr                      (i_csr_addr[11    :0]                           ),
.csr_rd                        (i_csr_addr_vld                                 ),
.intp_file_sel                 (intp_file_sel[INTP_FILE_WIDTH-1:0]             ),
.priv_is_illegal               (priv_is_illegal                                ),
.eip_final                     (eip_final                                      ),
.eip_sw                        (eip_sw                                         ),
.eip_sw_wr                     (eip_sw_wr                                      ),
.xtopei                        (xtopei                                         ),
.i_csr_v                       (i_csr_v                                        ),
.i_csr_wdata                   (i_csr_wdata[XLEN-1:0]                          ),
.i_csr_wdata_op                (i_csr_wdata_op[1:0]                            ),
.i_csr_wdata_vld               (i_csr_wdata_vld                                ),
.o_csr_rdata_vld               (o_csr_rdata_vld                                ),
.o_csr_rdata                   (o_csr_rdata[XLEN-1:0]                          ),
.o_csr_illegal                 (o_csr_illegal                                  ),
.o_irq                         (o_irq[NR_INTP_FILES-1:0]                       ) 
//.o_xtopei                      (xtopei_out                                     )
);
imsic_csr_gate #(
.NR_INTP_FILES      (NR_INTP_FILES  ),    
.XLEN               (XLEN           ),    
.NR_HARTS           (NR_HARTS       ),    
.NR_HARTS_WIDTH     (NR_HARTS_WIDTH ),    
.NR_SRC             (NR_SRC         ),    
.NR_SRC_WIDTH       (NR_SRC_WIDTH   ),    
.NR_REG             (NR_REG         ),    
.NR_REG_WIDTH       (NR_REG_WIDTH   ),  
.MSI_INFO_WIDTH     (MSI_INFO_WIDTH ),  
.EID_VLD_DLY        (EID_VLD_DLY_NUM),  
.INTP_FILE_WIDTH    (INTP_FILE_WIDTH)
)
u_imsic_csr_gate
(
.clk                          (csr_clk                                                  ),
.rstn                         (csr_rstn_low                                             ),
.hart_id                      (hart_id[NR_HARTS_WIDTH-1:0]                              ),
.i_msi_info                   (i_msi_info[MSI_INFO_WIDTH-1:0]                           ),
.i_msi_info_vld               (i_msi_info_vld                                           ),
.i_csr_addr_vld               (i_csr_addr_vld                                 ),
.i_csr_priv_lvl               (i_csr_priv_lvl[1:0]                                      ),
.i_csr_v                      (i_csr_v                                                  ),
.i_csr_vgein                  (i_csr_vgein[5:0]                                         ),
.i_csr_claim                  (i_csr_claim[2:0]                                         ),
.xtopei                       (xtopei                                                   ),
.vgein_legal                  (vgein_legal                                              ),
.intp_file_sel                (intp_file_sel[INTP_FILE_WIDTH-1:0]                       ),
.priv_is_illegal              (priv_is_illegal                                          ),
.eip_sw                       (eip_sw                                                   ),
.eip_sw_wr                    (eip_sw_wr                                                ),
.eip_final                    (eip_final                                                )
);

endmodule
