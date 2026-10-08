# Build the complete camera/ISP/DDR/HDMI + STM32 UART integration in TD 6.2.1.
# Commands follow the bundled SWUG105 and doc/scripts/DefaultFlow.tcl.
# No hardware is programmed by this script.
set integration_dir [file dirname [file normalize [info script]]]
set package_dir [file dirname $integration_dir]
set project_dir [file join $package_dir fpga traffic_sign_td td_project]
set source_dir [file join $package_dir fpga traffic_sign_td user_source]
set output_dir [file join $integration_dir td_bit]
set bit_dir [file join $project_dir bitstream]
file mkdir $output_dir
file mkdir $bit_dir
set start_stage all
if {[info exists ::env(CAR_TD_START_STAGE)]} {set start_stage $::env(CAR_TD_START_STAGE)}
if {$start_stage ni {all place route bitgen}} {error "Unsupported resume stage: $start_stage"}
set marker_file [file join $output_dir stages_${start_stage}.log]
set fd [open $marker_file w]
puts $fd "START $start_stage [clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}]"
close $fd
proc mark {message} {
    global marker_file
    set fd [open $marker_file a]
    puts $fd "$message [clock format [clock seconds] -gmt 1 -format {%Y-%m-%dT%H:%M:%SZ}]"
    close $fd
    # Hidden Windows launches may not create a Tcl stdout channel. The file
    # marker is authoritative; console progress is best effort only.
    catch {puts $message}
}
proc car_load_timing {} {
    global project_dir source_dir
    # This TD build can receive an empty filename from a fresh Tcl path object.
    # Materialize strings; do not pass [file join ...] directly to read_sdc.
    set car_main_sdc "$project_dir/traffic_sign_td.sdc"
    mark "CAR_MAIN_SDC=$car_main_sdc bytes=[file size $car_main_sdc]"
    read_sdc $car_main_sdc
    read_sdc -ip ddr2 "$source_dir/ip_source/ph1p35_ddr/ddr2/src/sdc/ddr2.sdc"
    read_sdc -ip w128_d512_fifo "$source_dir/ip_source/w128_d512_fifo/w128_d512_fifo.tcl"
}
proc car_check_clocks {report_file} {
    set car_fd [open $report_file r]
    set car_report [read $car_fd]
    close $car_fd
    if {![regexp {Constraint File[^\n]*traffic_sign_td\.sdc} $car_report]} {
        error "Main SDC is absent from timing report: $report_file"
    }
    foreach car_clock {sys_clk_50m MIPI_RX_BYTE_CLK HDMI_PIXEL_CLK HDMI_SERIAL_CLK mipi_rx_ck_pad /usr_clk /ddr_clk} {
        if {[string first $car_clock $car_report] < 0} {
            error "Required clock missing from timing report: $car_clock"
        }
    }
    mark CAR_BIT_CLOCK_CONSTRAINTS_OK
}
set canonical_project [file join $project_dir traffic_sign_td.al]
set fd [open $canonical_project r]
set config [read $fd]
close $fd
set car_original_project_text $config
proc car_restore_project {} {
    global canonical_project car_original_project_text
    set car_restore_fd [open $canonical_project w]
    puts -nonewline $car_restore_fd $car_original_project_text
    close $car_restore_fd
}
# Only this build copy is normalized; the delivered project remains untouched.
regsub {(<Project Version="3" Minor="2" Path=")[^"]*(")} $config "\\1$project_dir\\2" config
set fd [open $canonical_project w]
puts -nonewline $fd $config
close $fd
cd $project_dir
if {[catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project -single_run $canonical_project
    if {$start_stage eq "all"} {
        load_run_param -run syn_1
        elaborate -top design_top_wrapper
        mark CAR_BIT_ELABORATE_OK
        read_adc [file join $source_dir lab_ex_2026_nosoft constraints_source pin.adc]
        read_ip_adc -ip ddr2 -file [file join $source_dir ip_source ph1p35_ddr ddr2 src adc ddr2.adc]
        car_load_timing
        optimize_rtl
        report_area -file [file join $output_dir traffic_sign_td_rtl.area]
        mark CAR_BIT_RTL_OK
        optimize_gate -maparea [file join $output_dir traffic_sign_td_map.area] -packarea [file join $output_dir traffic_sign_td_pack.area]
        legalize_phy_inst
        # SWUG105 single-run flow reapplies timing after primitive legalization.
        # Do not clear_sdc here: this TD version loses already-started timer
        # constraints even after the files are re-added. Re-read in place as in
        # the documented single-run flow, and verify the clock report below.
        car_load_timing
        update_timing
        report_timing_status -file [file join $output_dir traffic_sign_td_gate.ts]
        report_timing_summary -file [file join $output_dir traffic_sign_td_gate.timing]
        export_db "$output_dir/traffic_sign_td_gate.db"
        car_check_clocks "$output_dir/traffic_sign_td_gate.timing"
        mark CAR_BIT_GATE_OK
    } elseif {$start_stage eq "place"} {
        import_db "$output_dir/traffic_sign_td_gate.db"
    } elseif {$start_stage eq "route"} {
        import_db "$output_dir/traffic_sign_td_place.db"
    } elseif {$start_stage eq "bitgen"} {
        import_db "$output_dir/traffic_sign_td_pr.db"
    }
    load_run_param -run phy_1
    if {$start_stage in {all place}} {
        place
        update_timing -mode manhattan
        report_timing_summary -file [file join $output_dir traffic_sign_td_place.timing]
        report_area -io_info -file [file join $output_dir traffic_sign_td_place.area]
        flow_status -file [file join $output_dir place_flow.status]
        # PH1P35/TD 6.2.168116 can terminate inside this OPTIONAL clock report.
        # Preserve required timing, area, flow status and checkpoint instead.
        export_db "$output_dir/traffic_sign_td_place.db"
        mark CAR_BIT_PLACE_OK
    }
    if {$start_stage in {all place route}} {
        route
        update_timing -mode final
        report_timing_status -file [file join $output_dir traffic_sign_td_phy.ts]
        report_timing_summary -file [file join $output_dir traffic_sign_td_pr.timing]
        car_check_clocks "$output_dir/traffic_sign_td_pr.timing"
        report_timing_exception -file [file join $output_dir traffic_sign_td_exception.timing]
        report_area -io_info -file [file join $output_dir traffic_sign_td_phy.area]
        flow_status -file [file join $output_dir route_flow.status]
        export_db "$output_dir/traffic_sign_td_pr.db"
        mark CAR_BIT_ROUTE_OK
    }
    set bit_file "$bit_dir/traffic_sign_td_auto_exposure.bit"
    mark "CAR_BIT_OUTPUT=$bit_file"
    set_param bitgen compress on
    bitgen -bit $bit_file -compress -g {mclk_freq:33MHz boot_mode:mspix4}
    export_bitgen_param -file "$output_dir/bitgen_param.txt"
    if {![file exists $bit_file] || [file size $bit_file] == 0} {
        error "bitgen did not create a nonempty bit file"
    }
    mark "CAR_BIT_BITGEN_OK bytes=[file size $bit_file]"
    close_project
    # TD can serialize set_param bitgen options into a Property section that
    # this same TD build cannot reopen. Keep the original valid AL after runs.
    car_restore_project
    mark CAR_BIT_BUILD_OK
} message options]} {
    car_restore_project
    mark "CAR_BIT_BUILD_FAILED: $message"
    if {[dict exists $options -errorinfo]} {catch {puts stderr [dict get $options -errorinfo]}}
    exit 1
}
exit 0

