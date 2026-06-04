package main

import (
	"os"

	"github.com/leconio/knockport/internal/client"
)

var version = "dev"

func main() {
	os.Exit(client.Main(os.Args[1:], version, os.Stdout, os.Stderr))
}
