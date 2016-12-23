###############################################################################
## Digitizer2 logic constraints
##
## Author: Peter Würtz, TU Kaiserslautern (2016)
## Distributed under the terms of the GNU General Public License Version 3.
## The full license is in the file COPYING.txt, distributed with this software.
###############################################################################

# Placement
set_property BEL PLLE2_ADV [get_cells clk_core_main_inst/inst/plle2_adv_inst]
set_property LOC PLLE2_ADV_X0Y0 [get_cells clk_core_main_inst/inst/plle2_adv_inst]
set_property BEL MMCME2_ADV [get_cells clk_core_usb_inst/inst/mmcm_adv_inst]
set_property LOC MMCME2_ADV_X0Y0 [get_cells clk_core_usb_inst/inst/mmcm_adv_inst]

# Clock relation
# set_clock_groups -name async_usb_adc -asynchronous -group [get_clocks -include_generated_clocks USB_CLKOUT] -group [get_clocks -include_generated_clocks ADC_DACLK_P]

# Domain crossing between application and acquisition
set_false_path -from [get_pins {application_inst/global_conf_reg[0]/C}] -to [get_pins {application_inst/sync_global_conf/gen[0].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/global_conf_reg[1]/C}] -to [get_pins {application_inst/sync_global_conf/gen[1].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/global_conf_reg[2]/C}] -to [get_pins {application_inst/sync_global_conf/gen[2].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/global_conf_reg[3]/C}] -to [get_pins {application_inst/sync_global_conf/gen[3].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/global_conf_reg[4]/C}] -to [get_pins {application_inst/sync_global_conf/gen[4].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/global_conf_reg[5]/C}] -to [get_pins {application_inst/sync_global_conf/gen[5].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/global_conf_reg[6]/C}] -to [get_pins {application_inst/sync_global_conf/gen[6].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/global_conf_reg[7]/C}] -to [get_pins {application_inst/sync_global_conf/gen[7].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/global_conf_reg[8]/C}] -to [get_pins {application_inst/sync_global_conf/gen[8].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/global_conf_reg[9]/C}] -to [get_pins {application_inst/sync_global_conf/gen[9].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/global_conf_reg[10]/C}] -to [get_pins {application_inst/sync_global_conf/gen[10].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/global_conf_reg[11]/C}] -to [get_pins {application_inst/sync_global_conf/gen[11].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/global_conf_reg[12]/C}] -to [get_pins {application_inst/sync_global_conf/gen[12].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/global_conf_reg[13]/C}] -to [get_pins {application_inst/sync_global_conf/gen[13].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/global_conf_reg[14]/C}] -to [get_pins {application_inst/sync_global_conf/gen[14].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/global_conf_reg[15]/C}] -to [get_pins {application_inst/sync_global_conf/gen[15].sync_bit/d_meta_reg/D}]

set_false_path -from [get_pins {application_inst/acq_conf_in_main_reg[0]/C}] -to [get_pins {application_inst/sync_acq_conf/gen[0].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/acq_conf_in_main_reg[1]/C}] -to [get_pins {application_inst/sync_acq_conf/gen[1].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/acq_conf_in_main_reg[2]/C}] -to [get_pins {application_inst/sync_acq_conf/gen[2].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/acq_conf_in_main_reg[3]/C}] -to [get_pins {application_inst/sync_acq_conf/gen[3].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/acq_conf_in_main_reg[4]/C}] -to [get_pins {application_inst/sync_acq_conf/gen[4].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/acq_conf_in_main_reg[5]/C}] -to [get_pins {application_inst/sync_acq_conf/gen[5].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/acq_conf_in_main_reg[6]/C}] -to [get_pins {application_inst/sync_acq_conf/gen[6].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/acq_conf_in_main_reg[7]/C}] -to [get_pins {application_inst/sync_acq_conf/gen[7].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/acq_conf_in_main_reg[8]/C}] -to [get_pins {application_inst/sync_acq_conf/gen[8].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/acq_conf_in_main_reg[9]/C}] -to [get_pins {application_inst/sync_acq_conf/gen[9].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/acq_conf_in_main_reg[10]/C}] -to [get_pins {application_inst/sync_acq_conf/gen[10].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/acq_conf_in_main_reg[11]/C}] -to [get_pins {application_inst/sync_acq_conf/gen[11].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/acq_conf_in_main_reg[12]/C}] -to [get_pins {application_inst/sync_acq_conf/gen[12].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/acq_conf_in_main_reg[13]/C}] -to [get_pins {application_inst/sync_acq_conf/gen[13].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/acq_conf_in_main_reg[14]/C}] -to [get_pins {application_inst/sync_acq_conf/gen[14].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/acq_conf_in_main_reg[15]/C}] -to [get_pins {application_inst/sync_acq_conf/gen[15].sync_bit/d_meta_reg/D}]

set_false_path -from [get_pins {application_inst/a_threshold_in_main_reg[0]/C}] -to [get_pins {application_inst/sync_a_threshold/gen[0].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/a_threshold_in_main_reg[1]/C}] -to [get_pins {application_inst/sync_a_threshold/gen[1].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/a_threshold_in_main_reg[2]/C}] -to [get_pins {application_inst/sync_a_threshold/gen[2].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/a_threshold_in_main_reg[3]/C}] -to [get_pins {application_inst/sync_a_threshold/gen[3].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/a_threshold_in_main_reg[4]/C}] -to [get_pins {application_inst/sync_a_threshold/gen[4].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/a_threshold_in_main_reg[5]/C}] -to [get_pins {application_inst/sync_a_threshold/gen[5].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/a_threshold_in_main_reg[6]/C}] -to [get_pins {application_inst/sync_a_threshold/gen[6].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/a_threshold_in_main_reg[7]/C}] -to [get_pins {application_inst/sync_a_threshold/gen[7].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/a_threshold_in_main_reg[8]/C}] -to [get_pins {application_inst/sync_a_threshold/gen[8].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/a_threshold_in_main_reg[9]/C}] -to [get_pins {application_inst/sync_a_threshold/gen[9].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/a_threshold_in_main_reg[10]/C}] -to [get_pins {application_inst/sync_a_threshold/gen[10].sync_bit/d_meta_reg/D}]
set_false_path -from [get_pins {application_inst/a_threshold_in_main_reg[11]/C}] -to [get_pins {application_inst/sync_a_threshold/gen[11].sync_bit/d_meta_reg/D}]
