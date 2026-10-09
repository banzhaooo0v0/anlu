# Run from td_project/camera_to_dsi_display_Runs/phy_1 after routing passes.
# Importing the saved route in a fresh process avoids retaining router state.
set rc [catch {
    import_device ph1_35p.db -package PH1P35MDG324 -speed 3
    open_project camera_to_dsi_display.prj -noanalyze
    import_db camera_to_dsi_display_pr.db
    commit_param -step bitgen
    set_param flow thread 1
    # TD 6.2.168116 compressed bitgen crashes on this routed design.
    set_param bitgen compress off
    bitgen -bit camera_to_dsi_display.bit
    puts "RESUME_BITGEN_PASS"
} result]
if {$rc} {
    puts "RESUME_BITGEN_FAILED: $result"
    exit 1
}
exit 0
