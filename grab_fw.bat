@echo off

mkdir firmware\qcom\x1e80100\microsoft\Denali
mkdir firmware\ath12k\WCN7850\hw2.0

copy C:\Windows\System32\qcdxkmsuc8380.mbn firmware\qcom\x1e80100\microsoft\
copy C:\Windows\System32\DriverStore\FileRepository\surfacepro_ext_adsp8380.inf_arm64_1067fbcaa7f43f02\adsp_dtbs.elf firmware\qcom\x1e80100\microsoft\Denali\adsp_dtb.mbn
copy C:\Windows\System32\DriverStore\FileRepository\surfacepro_ext_adsp8380.inf_arm64_1067fbcaa7f43f02\qcadsp8380.mbn firmware\qcom\x1e80100\microsoft\Denali\qcadsp8380.mbn
copy C:\Windows\System32\DriverStore\FileRepository\qcsubsys_ext_cdsp8380.inf_arm64_9ed31fd1359980a9\cdsp_dtbs.elf firmware\qcom\x1e80100\microsoft\Denali\cdsp_dtb.mbn
copy C:\Windows\System32\DriverStore\FileRepository\qcsubsys_ext_cdsp8380.inf_arm64_9ed31fd1359980a9\qccdsp8380.mbn firmware\qcom\x1e80100\microsoft\Denali\qccdsp8380.mbn
copy C:\Windows\System32\DriverStore\FileRepository\qcwlanhmt8380.inf_arm64_b6e9acfd0d644720\wlanfw20.mbn firmware\ath12k\WCN7850\hw2.0\amss.bin
copy C:\Windows\System32\DriverStore\FileRepository\qcwlanhmt8380.inf_arm64_b6e9acfd0d644720\bdwlan.elf firmware\ath12k\WCN7850\hw2.0\board.bin
copy C:\Windows\System32\DriverStore\FileRepository\qcwlanhmt8380.inf_arm64_b6e9acfd0d644720\phy_ucode20.elf firmware\ath12k\WCN7850\hw2.0\m3.bin
