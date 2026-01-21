module test-license-compliance

go 1.21

require (
	// 🟡 MEDIUM RISK - EPL/MPL Licenses
	github.com/eclipse/paho.mqtt.golang v1.4.3

	// 🟢 LOW RISK - MIT/Apache/BSD Licenses
	github.com/gin-gonic/gin v1.9.1
	github.com/gorilla/mux v1.8.1
	github.com/stretchr/testify v1.8.4
	go.uber.org/zap v1.26.0
	github.com/spf13/cobra v1.8.0
	github.com/sirupsen/logrus v1.9.3
	gorm.io/gorm v1.25.5
	github.com/golang/protobuf v1.5.3
	
	// Additional packages
	github.com/goccy/go-graphviz v0.1.2
	github.com/miekg/dns v1.1.58
	golang.org/x/crypto v0.17.0
	golang.org/x/net v0.19.0
	golang.org/x/text v0.14.0
	gopkg.in/yaml.v2 v2.4.0
)
