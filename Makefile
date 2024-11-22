build: amd arm


amd:
	GOOS=linux GOARCH=amd64 go build -o bin/tags-linux-amd64 .

arm:
	GOOS=linux GOARCH=amd64 go build -o bin/tags-linux-arm64 .
