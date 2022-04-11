package main

import (
	"flag"
	"fmt"
	"io/ioutil"
	"log"
	"os"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/ec2metadata"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/ec2"
	"github.com/cenkalti/backoff/v4"
)

var metadata_url = "http://169.254.169.254/latest/meta-data/"
var (
	WarningLogger *log.Logger
	InfoLogger    *log.Logger
	ErrorLogger   *log.Logger
	verbosity     *bool
)

func main() {
	var fileName = flag.String("f", "", "Filename to write env vars to")
	flag.Parse()

	InfoLogger = log.New(os.Stdout, "INFO: ", log.Ldate|log.Ltime)
	WarningLogger = log.New(os.Stdout, "WARN: ", log.Ldate|log.Ltime)
	ErrorLogger = log.New(os.Stderr, "ERROR: ", log.Ldate|log.Ltime)
	region, instance_id := RegionInstanceId()

	tags, err := GetTags()

	if err != nil {
		exitErrorf("Unable to get tags")
	}
	envVarsString := fmt.Sprintf("REGION=\"%s\"\nINSTANCE_ID=\"%s\"\n", region, instance_id)
	envVarsString += TagsToString(tags)

	if *fileName != "" {
		err = ioutil.WriteFile(*fileName, []byte(envVarsString), 0644)
	} else {
		fmt.Println(envVarsString)
	}
	if err != nil {
		exitErrorf("Error writing to file %s", *fileName)
	}

}

func exitErrorf(msg string, args ...interface{}) {
	ErrorLogger.Printf(msg+"\n", args...)
	os.Exit(1)
}

func TagsToString(tagMap map[string]string) string {
	var toString string
	for key, value := range tagMap {
		key = strings.ToUpper(key)
		key = strings.ReplaceAll(key, ":", "_")
		key = strings.ReplaceAll(key, ".", "_")
		toString += fmt.Sprintf("%s=\"%s\"\n", key, value)
	}
	return toString
}

func RegionInstanceId(idnentityDocument ...ec2metadata.EC2InstanceIdentityDocument) (region string, instanceID string) {
	var ec2InstanceIdentifyDocument ec2metadata.EC2InstanceIdentityDocument
	if len(idnentityDocument) > 0 {
		ec2InstanceIdentifyDocument = idnentityDocument[0]
	} else {
		c := ec2metadata.New(session.New())
		ec2InstanceIdentifyDocument, _ = c.GetInstanceIdentityDocument()
	}

	region = ec2InstanceIdentifyDocument.Region
	instanceID = ec2InstanceIdentifyDocument.InstanceID
	//fmt.Println(instanceID)
	return
}

func GetTags() (tagmap map[string]string, err error) {
	b := backoff.NewExponentialBackOff()
	b.MaxElapsedTime = 3 * time.Minute

	region, instanceID := RegionInstanceId()
	sess, err := session.NewSession(&aws.Config{
		Region: aws.String(region)},
	)
	if err != nil {
		exitErrorf("Unable to establish an AWS session")
	}
	svc := ec2.New(sess)
	tagMap := make(map[string]string)

	params := &ec2.DescribeInstancesInput{
		InstanceIds: []*string{
			aws.String(instanceID),
		},
	}
	var resp *ec2.DescribeInstancesOutput

	backoffErr := backoff.Retry(func() error {
		resp, err = svc.DescribeInstances(params)
		if err != nil {
			return err
		} else {
			return nil
		}
	}, b)

	if backoffErr != nil {
		fmt.Printf("Error describing instances: %s", backoffErr)
		return tagMap, backoffErr
	}
	if len(resp.Reservations) == 0 {
		return tagMap, err
	}
	for idx := range resp.Reservations {
		for _, inst := range resp.Reservations[idx].Instances {
			for _, tag := range inst.Tags {

				tagMap[*tag.Key] = *tag.Value
			}
		}
	}
	return tagMap, nil
}
