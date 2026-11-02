package main

import (
	"fmt"
	"kindle-mtp-test/internal/mtp"
	"os"
)

func main() {
	mtp.Init()
	devs, err := mtp.Detect()
	if err != nil {
		fmt.Println("detect error:", err)
		os.Exit(1)
	}
	fmt.Printf("found %d device(s)\n", len(devs))
	for _, d := range devs {
		fmt.Printf("bus=%d dev=%d VID=%04x PID=%04x vendor=%s product=%s\n", d.Bus, d.DevNum, d.VendorID, d.ProductID, d.Vendor, d.Product)
		if d.VendorID == 0x1949 {
			m, err := mtp.Open(d)
			if err != nil {
				fmt.Println("open error:", err)
				continue
			}
			fmt.Println("info:", mtp.DeviceInfo(m))
			files := mtp.ListFiles(m)
			fmt.Printf("files: %d\n", len(files))
			for _, f := range files {
				fmt.Println("  ", f)
			}
			mtp.Close(m)
		}
	}
}
