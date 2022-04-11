package main

import (
	"testing"

	"github.com/aws/aws-sdk-go/aws/client"
	"github.com/aws/aws-sdk-go/aws/ec2metadata"
)

type mockEC2Metadata struct {
	*client.Client
}

func (m *mockEC2Metadata) GetInstanceIdentityDocument() (ec2metadata.EC2InstanceIdentityDocument, error) {
	return ec2metadata.EC2InstanceIdentityDocument{}, nil
}

func TestTagsToString(t *testing.T) {
	normalTag := map[string]string{"name": "this-name"}
	normalResp := "NAME=\"this-name\"\n"
	resp := TagsToString(normalTag)
	if normalResp != resp {
		t.Errorf("got %q, wanted %q", resp, normalResp)
	}

	dotTag := map[string]string{"Adobe.Env": "Production"}
	dotResp := "ADOBE_ENV=\"Production\"\n"
	resp = TagsToString(dotTag)
	if dotResp != resp {
		t.Errorf("got %q, wanted %q", resp, dotResp)
	}

}
