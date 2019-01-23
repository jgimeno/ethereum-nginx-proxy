package main

import "C"

import (
	"github.com/VideoCoin/go-videocoin/core/types"
	"github.com/VideoCoin/go-videocoin/rlp"
)

func main() {}

//export DeriveSender
func DeriveSender(rawTx []byte) string {
	tx := new(types.Transaction)
	if err := rlp.DecodeBytes(rawTx, tx); err != nil {
		return ""
	}
	from, err := types.Sender(types.NewEIP155Signer(tx.ChainId()), tx)
	if err != nil {
		return ""
	}

	return from.String()
}
