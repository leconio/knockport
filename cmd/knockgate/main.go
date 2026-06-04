package main

import (
	"fmt"
	"os"

	"github.com/leconio/knockport/internal/app"
	"github.com/leconio/knockport/internal/ui"
)

var version = "dev"

func main() {
	if len(os.Args) == 2 && os.Args[1] == "version" {
		fmt.Println(version)
		return
	}
	app.Version = version
	if err := app.Run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, ui.Red(ui.T("错误：", "ERROR: ")+err.Error()))
		os.Exit(1)
	}
}
