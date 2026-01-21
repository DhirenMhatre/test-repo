module test-license-compliance

go 1.21

require (
	// GPL-3.0 licensed packages
	github.com/goccy/go-graphviz v0.1.2

	// LGPL licensed packages
	github.com/miekg/dns v1.1.58

	// Packages with known CVEs
	github.com/dgrijalva/jwt-go v3.2.0+incompatible
	golang.org/x/crypto v0.0.0-20210711020723-a769d52b0f97
	golang.org/x/net v0.0.0-20211112202133-69e39bad7dc2
	golang.org/x/text v0.3.7
	gopkg.in/yaml.v2 v2.4.0

	// Apache/MIT licensed (permissive - for comparison)
	github.com/gin-gonic/gin v1.9.1
	github.com/gorilla/mux v1.8.1
	github.com/sirupsen/logrus v1.9.3
)
