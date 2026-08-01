package service

import (
	"context"
	"crypto/tls"
	"errors"
	"fmt"
	"net"
	"net/http"
	"net/netip"
	"net/smtp"
	"net/url"
	"strconv"
	"strings"
	"time"
)

var ErrOutboundAddressNotAllowed = errors.New("outbound address is not allowed")

const outboundRequestTimeout = 10 * time.Second

// outboundNetworkPolicy resolves and validates every destination immediately
// before dialing it. This prevents user-controlled integrations from reaching
// loopback, private, link-local, and other special-purpose networks by default.
type outboundNetworkPolicy struct {
	allowPrivateNetworks bool
	resolver             *net.Resolver
	dialer               *net.Dialer
}

func newOutboundNetworkPolicy(allowPrivateNetworks bool) *outboundNetworkPolicy {
	return &outboundNetworkPolicy{
		allowPrivateNetworks: allowPrivateNetworks,
		resolver:             net.DefaultResolver,
		dialer: &net.Dialer{
			Timeout:   outboundRequestTimeout,
			KeepAlive: 30 * time.Second,
		},
	}
}

func newSafeOutboundHTTPClient(allowPrivateNetworks bool) *http.Client {
	policy := newOutboundNetworkPolicy(allowPrivateNetworks)
	transport := http.DefaultTransport.(*http.Transport).Clone()
	// Do not inherit an ambient proxy: a proxy could resolve an otherwise
	// blocked private destination on behalf of the application.
	transport.Proxy = nil
	transport.DialContext = policy.dialContext
	transport.TLSClientConfig = &tls.Config{MinVersion: tls.VersionTLS12}

	return &http.Client{
		Transport: transport,
		Timeout:   outboundRequestTimeout,
		CheckRedirect: func(req *http.Request, via []*http.Request) error {
			if len(via) >= 5 {
				return errors.New("too many redirects")
			}
			return validateOutboundURL(req.URL.String(), allowPrivateNetworks)
		},
	}
}

func validateOutboundURL(rawURL string, allowPrivateNetworks bool) error {
	parsed, err := url.ParseRequestURI(strings.TrimSpace(rawURL))
	if err != nil || parsed == nil || parsed.Host == "" || parsed.Opaque != "" {
		return ErrOutboundAddressNotAllowed
	}
	if parsed.User != nil || parsed.Fragment != "" {
		return ErrOutboundAddressNotAllowed
	}

	scheme := strings.ToLower(parsed.Scheme)
	if scheme != "https" && scheme != "http" {
		return ErrOutboundAddressNotAllowed
	}
	// Cleartext outbound requests are only available behind the operator's
	// explicit private-network opt-in (for example, a local AI gateway).
	if scheme == "http" && !allowPrivateNetworks {
		return ErrOutboundAddressNotAllowed
	}

	host := strings.TrimSpace(parsed.Hostname())
	if host == "" || strings.Contains(host, "%") {
		return ErrOutboundAddressNotAllowed
	}
	if port := parsed.Port(); port != "" {
		value, err := strconv.Atoi(port)
		if err != nil || value < 1 || value > 65535 {
			return ErrOutboundAddressNotAllowed
		}
	}

	if strings.EqualFold(host, "localhost") && !allowPrivateNetworks {
		return ErrOutboundAddressNotAllowed
	}
	if ip := net.ParseIP(host); ip != nil && !allowPrivateNetworks && isBlockedOutboundIP(ip) {
		return ErrOutboundAddressNotAllowed
	}
	return nil
}

func (p *outboundNetworkPolicy) dialContext(ctx context.Context, network, address string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(address)
	if err != nil || strings.TrimSpace(host) == "" || strings.Contains(host, "%") {
		return nil, ErrOutboundAddressNotAllowed
	}

	var addresses []net.IPAddr
	if ip := net.ParseIP(host); ip != nil {
		addresses = []net.IPAddr{{IP: ip}}
	} else {
		addresses, err = p.resolver.LookupIPAddr(ctx, host)
		if err != nil {
			return nil, err
		}
	}
	if len(addresses) == 0 {
		return nil, errors.New("outbound host did not resolve")
	}

	for _, resolved := range addresses {
		if resolved.Zone != "" || (!p.allowPrivateNetworks && isBlockedOutboundIP(resolved.IP)) {
			return nil, ErrOutboundAddressNotAllowed
		}
	}

	var dialErr error
	for _, resolved := range addresses {
		target := net.JoinHostPort(resolved.IP.String(), port)
		conn, err := p.dialer.DialContext(ctx, network, target)
		if err == nil {
			return conn, nil
		}
		dialErr = err
	}
	return nil, dialErr
}

var blockedOutboundPrefixes = []netip.Prefix{
	netip.MustParsePrefix("0.0.0.0/8"),
	netip.MustParsePrefix("10.0.0.0/8"),
	netip.MustParsePrefix("100.64.0.0/10"),
	netip.MustParsePrefix("127.0.0.0/8"),
	netip.MustParsePrefix("169.254.0.0/16"),
	netip.MustParsePrefix("172.16.0.0/12"),
	netip.MustParsePrefix("192.0.0.0/24"),
	netip.MustParsePrefix("192.0.2.0/24"),
	netip.MustParsePrefix("192.168.0.0/16"),
	netip.MustParsePrefix("198.18.0.0/15"),
	netip.MustParsePrefix("198.51.100.0/24"),
	netip.MustParsePrefix("203.0.113.0/24"),
	netip.MustParsePrefix("224.0.0.0/4"),
	netip.MustParsePrefix("240.0.0.0/4"),
	netip.MustParsePrefix("::/128"),
	netip.MustParsePrefix("::1/128"),
	netip.MustParsePrefix("64:ff9b::/96"),
	netip.MustParsePrefix("64:ff9b:1::/48"),
	netip.MustParsePrefix("100::/64"),
	netip.MustParsePrefix("2001::/23"),
	netip.MustParsePrefix("2001:db8::/32"),
	netip.MustParsePrefix("fc00::/7"),
	netip.MustParsePrefix("fe80::/10"),
	netip.MustParsePrefix("ff00::/8"),
}

func isBlockedOutboundIP(ip net.IP) bool {
	address, ok := netip.AddrFromSlice(ip)
	if !ok {
		return true
	}
	address = address.Unmap()
	if !address.IsValid() || !address.IsGlobalUnicast() {
		return true
	}
	for _, prefix := range blockedOutboundPrefixes {
		if prefix.Contains(address) {
			return true
		}
	}
	return false
}

func sendSMTPMessage(
	policy *outboundNetworkPolicy,
	host string,
	port int,
	auth smtp.Auth,
	from string,
	recipients []string,
	message []byte,
) error {
	host = strings.TrimSpace(host)
	if policy == nil || validateOutboundHostPort(host, port, policy.allowPrivateNetworks) != nil {
		return ErrOutboundAddressNotAllowed
	}

	ctx, cancel := context.WithTimeout(context.Background(), outboundRequestTimeout)
	defer cancel()
	conn, err := policy.dialContext(ctx, "tcp", net.JoinHostPort(host, strconv.Itoa(port)))
	if err != nil {
		return err
	}
	defer conn.Close()
	if err := conn.SetDeadline(time.Now().Add(outboundRequestTimeout)); err != nil {
		return err
	}

	if port == 465 {
		tlsConn := tls.Client(conn, &tls.Config{ServerName: host, MinVersion: tls.VersionTLS12})
		if err := tlsConn.HandshakeContext(ctx); err != nil {
			return err
		}
		conn = tlsConn
	}

	client, err := smtp.NewClient(conn, host)
	if err != nil {
		return err
	}
	defer client.Close()

	if port != 465 {
		if ok, _ := client.Extension("STARTTLS"); !ok {
			return errors.New("smtp server does not support TLS")
		}
		if err := client.StartTLS(&tls.Config{ServerName: host, MinVersion: tls.VersionTLS12}); err != nil {
			return err
		}
	}
	if auth != nil {
		if ok, _ := client.Extension("AUTH"); !ok {
			return errors.New("smtp server does not support authentication")
		}
		if err := client.Auth(auth); err != nil {
			return err
		}
	}
	if err := client.Mail(from); err != nil {
		return err
	}
	for _, recipient := range recipients {
		if err := client.Rcpt(recipient); err != nil {
			return err
		}
	}
	writer, err := client.Data()
	if err != nil {
		return err
	}
	if _, err := writer.Write(message); err != nil {
		_ = writer.Close()
		return err
	}
	if err := writer.Close(); err != nil {
		return err
	}
	if err := client.Quit(); err != nil {
		return fmt.Errorf("smtp quit: %w", err)
	}
	return nil
}

func validateOutboundHostPort(host string, port int, allowPrivateNetworks bool) error {
	host = strings.TrimSpace(host)
	if host == "" || port < 1 || port > 65535 || strings.Contains(host, "%") {
		return ErrOutboundAddressNotAllowed
	}
	if strings.ContainsAny(host, " /?#@") {
		return ErrOutboundAddressNotAllowed
	}
	if strings.EqualFold(host, "localhost") && !allowPrivateNetworks {
		return ErrOutboundAddressNotAllowed
	}
	if ip := net.ParseIP(host); ip != nil && !allowPrivateNetworks && isBlockedOutboundIP(ip) {
		return ErrOutboundAddressNotAllowed
	}
	return nil
}
