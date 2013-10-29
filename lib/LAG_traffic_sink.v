/* -------------------------------------------------------------------------------
 * (C)2007 Robert Mullins
 * Computer Architecture Group, Computer Laboratory
 * University of Cambridge, UK.
 * -------------------------------------------------------------------------------
 *
 *   *** NOT FOR SYNTHESIS ***
 * 
 * Traffic Sink
 * 
 * Collects incoming packets and produces statistics. 
 * 
 *  - check flit id's are sequential
 * 
 */
//`include "parameters.v"

module LAG_traffic_sink (flit_in, cntrl_out, rec_count, stats, clk, rst_n);
   
   parameter xdim = 4;
   parameter ydim = 4; 
   
   parameter xpos = 0;
   parameter ypos = 0;

   parameter warmup_packets = 100;
   parameter measurement_packets = 1000;

   parameter router_num_pls_on_exit = 1;
   
   input     flit_t flit_in [router_num_pls_on_exit-1:0];
   output    chan_cntrl_t cntrl_out;
   output    sim_stats_t stats;
   input     clk, rst_n;
   output    integer rec_count;

   integer   expected_flit_id [router_num_pls_on_exit-1:0];
   integer   head_injection_time [router_num_pls_on_exit-1:0];
   integer   latency, sys_time;
   integer   j, i;
   
   genvar ch;
    
   
   for (ch=0; ch<router_num_pls; ch++) begin:flow_control
    always@(posedge clk) begin
      if (!rst_n) begin	   
        cntrl_out.credits[ch] <= 0;	 
      end else begin
        if (flit_in[ch].control.valid) begin
          if (ch < router_num_pls_on_exit) begin
            cntrl_out.credits[ch] <= 1;
          end else begin
            $display ("%m: Error: Flit Channel ID is out-of-range for exit from network!");
	          $display ("Channel ID = %1d (router_num_pls_on_exit=%1d)", ch, router_num_pls_on_exit);
	          $finish;
          end
        end else begin
          cntrl_out.credits[ch] <= 0;
        end
      end
    end   
   end

   
   always@(posedge clk) begin
      if (!rst_n) begin
	   
         rec_count=0;
      	 stats.total_latency=0;
      	 stats.total_hops=0;
      	 stats.max_hops=0;
      	 stats.min_hops=MAXINT;
      	 stats.max_latency=0;
      	 stats.min_latency=MAXINT;
      	 stats.measure_start=-1;
      	 stats.measure_end=-1;
      	 stats.flit_count=0;
  	 
         for (j=0; j<router_num_pls_on_exit; j++) begin
      	    expected_flit_id[j]=1;
      	    head_injection_time[j]=-1;
      	 end
      	 
      	 for (j=0; j<(xdim+ydim); j++) begin
      	    stats.total_lat_for_hop_count[j]=0;
      	    stats.total_packets_with_hop_count[j]=0;
      	 end
      
      	 for (j=0; j<=100; j++) begin
      	    stats.lat_freq[j]=0;
      	 end
	 
	       sys_time = 0;
	 
      end else begin // if (!rst_n)
	 
        sys_time++;
	 
	   for (i=0; i<router_num_pls_on_exit; i++) begin
	 if (flit_in[i].control.valid) begin
            
      //$display ("%m: Packet %d arrived!!!", rec_count);
	    
	    //
	    // check flit was destined for this node!
	    //
	    if ((flit_in[i].debug.xdest!=xpos)||(flit_in[i].debug.ydest!=ypos)) begin
	       $display ("%m: Error: Flit arrived at wrong destination!");
	       $finish;
	    end

	    //
	    // check flit didn't originate at this node
	    //
	    if ((flit_in[i].debug.xdest==flit_in[i].debug.xsrc)&&
		(flit_in[i].debug.ydest==flit_in[i].debug.ysrc)) begin
	       $display ("%m: Error: Received flit originated from this node?");
	       $finish;
	    end
	    
	    //
	    // check flits for each packet are received in order
	    //
	    if (flit_in[i].debug.flit_id != expected_flit_id[i]) begin
	       $display ("%m: Error: Out of sequence flit received? (packet generated at %1d,%1d)",
			 flit_in[i].debug.xsrc, flit_in[i].debug.ysrc);
	       $display ("-- Flit ID = %1d, Expected = %1d", flit_in[i].debug.flit_id, expected_flit_id[i]);
	       $display ("-- Packet ID = %1d", flit_in[i].debug.packet_id);
	       $finish;
	    end else begin

//	       $display ("%m: Rec: Flit ID = %1d, Packet ID = %1d, PL ID=%1d", 
//			 flit_in.debug.flit_id, flit_in.debug.packet_id, flit_in.control.pl_id);
	    end

	    expected_flit_id[i]++;
	    
//	    $display ("rec flit");

	    // #####################################################################
	    // Head of new packet has arrived
	    // #####################################################################
	    if (flit_in[i].debug.flit_id==1) begin
//	       $display ("%m: new head, current_pl=%1d, inject_time=%1d", current_pl, flit_in.debug.inject_time);
	       head_injection_time[i] = flit_in[i].debug.inject_time;
	    end

	    // count all flits received in measurement period
	    if ((flit_in[i].debug.packet_id>warmup_packets) && (stats.measure_start==-1))  stats.measure_start= sys_time;
	    if (flit_in[i].debug.packet_id<=warmup_packets+measurement_packets)
	      if (stats.measure_start!=-1) stats.flit_count++;

	    
	    // #####################################################################
	    // Tail of packet has arrived
	    // Remember, latency = (tail arrival time) - (head injection time)
	    // #####################################################################
	    if (flit_in[i].control.tail) begin

//	       $display ("%m: Tail Rec, Expected = 1");
	       
	       expected_flit_id[i]=1;

	       if ((flit_in[i].debug.packet_id>warmup_packets) &&
		   (flit_in[i].debug.packet_id<=warmup_packets+measurement_packets)) begin

		  rec_count++;

		  // time last measurement packet was received
		  stats.measure_end = sys_time;
		  
		  //
		  // gather latency stats.
		  //
		  latency = sys_time - head_injection_time[i]; 
		  stats.total_latency = stats.total_latency + latency;

		  stats.min_latency = min (stats.min_latency, latency);
		  stats.max_latency = max (stats.max_latency, latency);

//		  $display ("%m: latency=%1d, sys_time=%1d, head_time[%1d]=%1d", latency, sys_time,
//			    current_pl, head_injection_time[current_pl]);
		  
		  //
		  // display progress estimate
		  //
		  if (rec_count%(measurement_packets/100)==0) 
		    $display ("%1d: %m: %1.2f%% complete (this packet's latency was %1d)", sys_time, 
			      $itor(rec_count*100)/$itor(measurement_packets),
			      latency);
		  
		  //
		  // sum latencies for different packet distances (and keep total distance travelled by all packets)
		  //
//		  $display ("This packet travelled %1d hops", flit_in.debug.hops);
		  stats.total_hops = stats.total_hops + flit_in[i].debug.hops;

		  stats.min_hops = min (stats.min_hops, flit_in[i].debug.hops);
		  stats.max_hops = max (stats.max_hops, flit_in[i].debug.hops);

		  stats.total_lat_for_hop_count[flit_in[i].debug.hops]=
					     stats.total_lat_for_hop_count[flit_in[i].debug.hops]+latency;
		  stats.total_packets_with_hop_count[flit_in[i].debug.hops]++;
		  
		  //
		  // bin latencies
		  //	
		  stats.lat_freq[min(latency, 100)]++;
	       end
	    end // if (flit_in.control.tail)
	    
	 end // if flit valid
	 end //for
      end  //if(!rst_n)
   end //always
   
endmodule
