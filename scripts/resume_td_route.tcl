# Resume the existing placement checkpoint without changing RTL or constraints.
# Run from td_project/camera_to_dsi_display_Runs/phy_1.
# A single worker is used to investigate the TD detailed-router crash.
set rc [catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project camera_to_dsi_display.prj -noanalyze
    import_db camera_to_dsi_display_place.db
    commit_param -step route
    set_param flow thread 1
    report_param
    route
    report_area -io_info -file camera_to_dsi_display_phy.area
    update_timing -mode final
    report_timing_summary -file camera_to_dsi_display_pr.timing
    report_timing_exception -file camera_to_dsi_display_exception.timing
    report_route_status -drc
    export_db camera_to_dsi_display_pr.db
    commit_param -step bitgen
    set_param bitgen compress off
    bitgen -bit camera_to_dsi_display.bit
    puts "RESUME_ROUTE_BITGEN_PASS"
} result]
if {$rc} {
    puts "RESUME_ROUTE_FAILED: $result"
    exit 1
}
exit 0
