package main

import (
	"fmt"
	"os"

	"github.com/kindle-manager/kindle-manager/internal/converter"
	"github.com/kindle-manager/kindle-manager/internal/library"
	"github.com/kindle-manager/kindle-manager/internal/storage"
)

func main() {
	if len(os.Args) < 2 {
		fmt.Println("usage: kindle-core <dbpath> <scan-root>")
		return
	}
	db, err := storage.Open(os.Args[1])
	if err != nil {
		fmt.Println("db:", err)
		return
	}
	defer db.Close()
	sc := library.NewScanner(db)
	if len(os.Args) >= 3 {
		n, err := sc.ScanRoot(os.Args[2])
		fmt.Printf("scanned %d books, err=%v\n", n, err)
	}
	books, _ := db.Books()
	fmt.Printf("library has %d books\n", len(books))
	cal, err := converter.DetectCalibre()
	if err != nil {
		fmt.Println("calibre:", err)
	} else {
		fmt.Println("calibre:", cal.Path, cal.Version)
	}
}
