package main

import (
	"fmt"
	"os"

	"github.com/mint-bookshelf/mint-bookshelf/internal/converter"
	"github.com/mint-bookshelf/mint-bookshelf/internal/library"
	"github.com/mint-bookshelf/mint-bookshelf/internal/storage"
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
		result, err := sc.ScanRoot(os.Args[2])
		fmt.Printf("scanned %d books, added=%d updated=%d moved=%d deleted=%d, err=%v\n",
			result.Scanned, result.Added, result.Updated, result.Moved, result.Deleted, err)
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
