package main

import (
  "bufio"
  "fmt"
  "net"
  "strconv"
  "strings"
  "sync/atomic"
  "time"
)

func startFIXServer() {
  listener, err := net.Listen("tcp", "127.0.0.1:5001")
  if err != nil {
    fmt.Printf("[FIX] listener failed: %v\n", err)
    return
  }
  fmt.Println("⚡ [FIX 4.4 Engine] Core structural listener online at TCP port :5001...")

  for {
    conn, err := listener.Accept()
    if err != nil {
      continue
    }
    go handleFIXConnection(conn)
  }
}

func handleFIXConnection(conn net.Conn) {
  defer conn.Close()
  reader := bufio.NewReader(conn)
  for {
    raw, err := reader.ReadString('\x01')
    if err != nil {
      return
    }
    message := strings.TrimRight(raw, "\x01")
    if message == "" {
      continue
    }
    fields := parseFIX(message)
    if fields["35"] != "D" {
      continue
    }

    sideValue := fields["54"]
    side := uint8(0)
    if sideValue == "2" {
      side = 1
    }

    price, errPrice := strconv.ParseFloat(fields["44"], 64)
    qty, errQty := strconv.ParseFloat(fields["38"], 64)
    if errPrice != nil || errQty != nil || price <= 0 || qty <= 0 {
      _, _ = conn.Write([]byte("8=FIX.4.4|35=8|39=8|150=8|58=invalid order|10=000\x01"))
      continue
    }

    write := atomic.LoadUint32(&buffer.WriteIndex)
    read := atomic.LoadUint32(&buffer.ReadIndex)
    if write-read >= capacity {
      _, _ = conn.Write([]byte("8=FIX.4.4|35=8|39=4|150=8|58=queue full|10=000\x01"))
      continue
    }

    orderID := uint64(time.Now().UnixNano())
    packet := orderPacket{
      OrderID:  orderID,
      UserID:   9999,
      Price:    uint64(price * scale),
      Quantity: uint64(qty * scale),
      Side:     side,
      Type:     0,
    }
    buffer.Queue[write%capacity] = packet
    atomic.StoreUint32(&buffer.WriteIndex, write+1)

    clOrdID := fields["11"]
    if clOrdID == "" {
      clOrdID = strconv.FormatUint(orderID, 10)
    }
    report := fmt.Sprintf("8=FIX.4.4|35=8|11=%s|37=%d|39=0|150=0|54=%s|44=%s|38=%s|10=000\x01", clOrdID, orderID, sideValue, fields["44"], fields["38"])
    _, _ = conn.Write([]byte(report))
  }
}

func parseFIX(message string) map[string]string {
  fields := make(map[string]string)
  parts := strings.Split(message, "|")
  for _, part := range parts {
    if part == "" {
      continue
    }
    kv := strings.SplitN(part, "=", 2)
    if len(kv) != 2 {
      continue
    }
    fields[kv[0]] = kv[1]
  }
  return fields
}
