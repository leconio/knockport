package ui

import (
	"bufio"
	"fmt"
	"os"
	"strings"
)

var enabled = os.Getenv("NO_COLOR") == ""

func color(code, text string) string {
	if !enabled {
		return text
	}
	return code + text + "\033[0m"
}

func Red(text string) string     { return color("\033[31;1m", text) }
func Green(text string) string   { return color("\033[32m", text) }
func Yellow(text string) string  { return color("\033[33m", text) }
func Cyan(text string) string    { return color("\033[36;1m", text) }
func Magenta(text string) string { return color("\033[35m", text) }

func Prompt(label, def string) string {
	reader := bufio.NewReader(os.Stdin)
	if def == "" {
		fmt.Printf("%s: ", Magenta(label))
	} else {
		fmt.Printf("%s [%s]: ", Magenta(label), def)
	}
	text, _ := reader.ReadString('\n')
	text = strings.TrimSpace(text)
	if text == "" {
		return def
	}
	return text
}

func Confirm(label string, def bool) bool {
	suffix := "[y/N]"
	if def {
		suffix = "[Y/n]"
	}
	answer := strings.ToLower(Prompt(label+" "+suffix, ""))
	if answer == "" {
		return def
	}
	return answer == "y" || answer == "yes"
}

func ConfirmYES(label string) bool {
	return strings.TrimSpace(Prompt(label+" 输入 YES 继续", "")) == "YES"
}
