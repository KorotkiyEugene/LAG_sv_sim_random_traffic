/* -------------------------------------------------------------------------------
 * (C)2012 Korotkyi Ievgen
 * National Technical University of Ukraine "Kiev Polytechnic Institute"
 * -------------------------------------------------------------------------------
 * 
 * Mesh Network with LAG
 * 
 */

module LAG_mesh_network (din, dout,
			input_full_flag,
			cntrl_in, 
			clk, rst_n);
   
   parameter XS=4;
   parameter YS=4;
   parameter NT=5;
   parameter NPL=4;
   parameter channel_latency=1;

   input     clk, rst_n;
   input     chan_cntrl_t cntrl_in [XS-1:0][YS-1:0] ; 
   input     flit_t din[XS-1:0][YS-1:0];
   output    flit_t dout[XS-1:0][YS-1:0][router_num_pls_on_exit-1:0];
   output    [router_num_pls_on_entry-1:0] input_full_flag [XS-1:0][YS-1:0];

   // record link utilisation
   // link_util[x][y][n] records activity of link attached to output port N of router at position (X, Y)  
   integer  link_util [XS-1:0][YS-1:0][NT-1:0][NPL-1:0]; 
   
   // network connections
   flit_t	 i_flit_in   [XS-1:0][YS-1:0][NT-1:0][NPL-1:0];
   flit_t	 i_flit_in_  [XS-1:0][YS-1:0][NT-1:0][NPL-1:0];  
   flit_t	 i_flit_out  [XS-1:0][YS-1:0][NT-1:0][NPL-1:0];
   flit_t	 i_flit_out_ [XS-1:0][YS-1:0][NT-1:0][NPL-1:0];

   flit_t	 terminator [NPL-1:0];

   integer   expected [XS-1:0][YS-1:0][NT-1:0][NPL-1:0];
   
   chan_cntrl_t  i_cntrl_in  [XS-1:0][YS-1:0][NT-1:0];
   chan_cntrl_t  i_cntrl_out [XS-1:0][YS-1:0][NT-1:0];
   chan_cntrl_t  i_cntrl_out_ [XS-1:0][YS-1:0][NT-1:0];

   integer 	 i,j,k,l;
   genvar 	 x,y,p,c;

   initial begin
      assert (router_radix==5) else begin
	 $display ("\n\nError: You must configure a 5 port router in order to build a mesh network!");
	 $display ("Parameter 'router_radix=%1d'\n\n", router_radix);
	 $fatal;
      end 
   end
   

   // *********************************************************

   generate
   for (y=0; y<YS; y=y+1) begin:yl
      for (x=0; x<XS; x=x+1) begin:xl

	 //
	 // make network connections
	 //
	 
	 // tile port - external interface
	 always_comb
	   begin
	 i_flit_in[x][y][`TILE] = terminator;
   i_flit_in[x][y][`TILE][0] = din[x][y]; 
     end

	 assign i_cntrl_in[x][y][`TILE].credits = cntrl_in[x][y].credits; 

   for (c=0; c<router_num_pls_on_exit; c++) begin:network_out_to_sink
	   assign dout[x][y][c] = i_flit_out[x][y][`TILE][c];
   end
   
	 // north port
	 if (y==0) begin
	    assign i_flit_in[x][y][`NORTH]  = terminator; 
	    assign i_cntrl_in[x][y][`NORTH] = '0; 
	 end else begin	    
	    assign i_flit_in[x][y][`NORTH]  = i_flit_out[x][y-1][`SOUTH];
	    assign i_cntrl_in[x][y][`NORTH] = i_cntrl_out[x][y-1][`SOUTH];
	 end

	 // east port
	 if (x==XS-1) begin
	    assign i_flit_in[x][y][`EAST]   = terminator; 
	    assign i_cntrl_in[x][y][`EAST]  = '0; 
	 end else begin
	    assign i_flit_in[x][y][`EAST]   = i_flit_out[x+1][y][`WEST];
	    assign i_cntrl_in[x][y][`EAST]  = i_cntrl_out[x+1][y][`WEST];
	 end

	 // south port
	 if (y==YS-1) begin
	    assign i_flit_in[x][y][`SOUTH]  = terminator;
	    assign i_cntrl_in[x][y][`SOUTH] = '0;
	 end else begin
	    assign i_flit_in[x][y][`SOUTH]  = i_flit_out[x][y+1][`NORTH];
	    assign i_cntrl_in[x][y][`SOUTH] = i_cntrl_out[x][y+1][`NORTH];
	 end

	 // west port
	 if (x==0) begin
	    assign i_flit_in[x][y][`WEST]   = terminator;
	    assign i_cntrl_in[x][y][`WEST]  = '0;
	 end else begin
	    assign i_flit_in[x][y][`WEST]   = i_flit_out[x-1][y][`EAST];
	    assign i_cntrl_in[x][y][`WEST]  = i_cntrl_out[x-1][y][`EAST];
	 end

	 for (p=0; p<NT; p++) begin:prts
	   for (c=0; c<NPL; c++) begin:channels2
      always_comb
	      begin
		    i_flit_in_[x][y][p][c] = i_flit_in[x][y][p][c];
		 
        // 
		    // Add one to hop count as flit enters router
		    // 
		      if (i_flit_in[x][y][p][c].control.valid) begin
		        i_flit_in_[x][y][p][c].debug.hops = i_flit_in[x][y][p][c].debug.hops+1;
		      end
     end
    end
     
	 end
	 
	 // ###################################
	 // Channel (link) between routers -    ** NOT FROM ROUTER TO TILE **
	 // ###################################
	 // i_flit_out_ -> CHANNEL -> i_flit_out
	 
   for (p=0; p<NT; p++) begin:prts2
	    if (p==`TILE) begin
	       // router to tile is a local connection
	       assign i_flit_out[x][y][p]=i_flit_out_[x][y][p];
	       assign i_cntrl_out[x][y][p] = i_cntrl_out_[x][y][p];
	    end else begin
	       LAG_pipelined_channel #(.nPC(NPL), .stages(channel_latency)) channel 
		 (.data_in(i_flit_out_[x][y][p]), .ctrl_in(i_cntrl_out_[x][y][p]),
		  .data_out(i_flit_out[x][y][p]), .ctrl_out(i_cntrl_out[x][y][p]), .clk, .rst_n);
	    end
	 end	 
	 
   // ###################################
	 // Router
	 // ###################################
	 // # parameters for router are read from parameters.v
	 LAG_router #(
                  .buf_len(router_buf_len),
        			    .network_x(network_x),
        			    .network_y(network_y),
        			    .NT(router_radix), 
        			    .NPL(router_num_pls),
        			    .alloc_stages(router_alloc_stages),
        			    .router_num_pls_on_entry(router_num_pls_on_entry),
        			    .router_num_pls_on_exit(router_num_pls_on_exit)
   )
   node 
	   (i_flit_in_[x][y], 
	    i_flit_out_[x][y], 
	    i_cntrl_in[x][y], 
	    i_cntrl_out_[x][y],
	    input_full_flag[x][y], 
	    clk, 
	    rst_n);


	 // debug
	 for (p=0; p<NT; p++) begin:prts3
	  for(c=0; c<NPL; c++) begin:channels3
      always@(posedge clk) begin
	       if (!rst_n) begin
	       end else begin
		    
        if (i_flit_out_[x][y][p][c].control.valid) begin
		      // link utilised
		      link_util[x][y][p][c]++;
		    end

`ifdef VERBOSE
      
		  if (i_flit_out[x][y][p][c].control.valid) begin

		     $display ("%1d: Router(%1d, %1d, OUT port=%1d channel=%1d) : flit (%1d) from (%1d, %1d) destined for (%1d, %1d)",
			       $time, x,y,p,c, 
			       i_flit_out_[x][y][p][c].debug.flit_id,
			       i_flit_out_[x][y][p][c].debug.xsrc,
			       i_flit_out_[x][y][p][c].debug.ysrc,
			       i_flit_out_[x][y][p][c].debug.xdest,
			       i_flit_out_[x][y][p][c].debug.ydest);
		  end   
`endif		     
		  if (i_flit_in[x][y][p][c].control.valid) begin

`ifdef VERBOSE
		     $display ("%1d: Router(%1d, %1d, IN  port=%1d channel=%1d) : flit (%1d) from (%1d, %1d) destined for (%1d, %1d)",
			       $time, x,y,p,c, 
			       i_flit_in_[x][y][p][c].debug.flit_id,
			       i_flit_in_[x][y][p][c].debug.xsrc,
			       i_flit_in_[x][y][p][c].debug.ysrc,
			       i_flit_in_[x][y][p][c].debug.xdest,
			       i_flit_in_[x][y][p][c].debug.ydest); 
`endif
		     
		     // check flit id. sequences are valid for each PL		     
		     if (i_flit_in_[x][y][p][c].debug.flit_id
			 !=expected[x][y][p][c]) begin
			$display ("%1d: Error: x=%1d, y=%1d, p=%1d, channel=%1d: flit_id=%1d, expected=%1d", $time, 
				  x,y,p,c, 
				  i_flit_in_[x][y][p][c].debug.flit_id,
				  expected[x][y][p][c]
				  );
			$display ("Flit originated from (%1d, %1d) and was destined for (%1d, %1d)",
				  i_flit_in_[x][y][p][c].debug.xsrc,
				  i_flit_in_[x][y][p][c].debug.ysrc,
				  i_flit_in_[x][y][p][c].debug.xdest,
				  i_flit_in_[x][y][p][c].debug.ydest);
			$finish;
		     end
		     
		     if (i_flit_in_[x][y][p][c].control.tail) begin
			expected[x][y][p][c]=1;
		     end else begin
			expected[x][y][p][c]++;
		     end
		     
		  end // if(i_flit_in[x][y][p][ch].control.valid)
	       end   //for
	    
      end //reset
	 end//always
	 
      end //for
      
   end //x
   end //y
   endgenerate
   

   initial begin
      for (i=0; i<XS; i++) begin
	 for (j=0; j<YS; j++) begin
	    for (k=0; k<NT; k++) begin
	       for (l=0; l<NPL; l++) begin
	    link_util[i][j][k][l]=0;   
		  expected[i][j][k][l]=1;
	       end
	    end
	 end
      end
      
    for (i=0; i<NPL; i++) begin
      terminator[i] = '0;
    end
      
   end // initial begin      
      
endmodule 
