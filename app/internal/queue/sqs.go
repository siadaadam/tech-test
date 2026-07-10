// Package queue wraps the SQS operations the API (producer) and consumer
// need. It relies on the AWS SDK's standard credential/region/endpoint
// resolution (including the AWS_ENDPOINT_URL_SQS env var), so the exact same
// code talks to a local SQS-compatible broker in dev and to real SQS in
// production - only environment variables change.
package queue

import (
	"context"
	"fmt"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/service/sqs"
	"github.com/aws/aws-sdk-go-v2/service/sqs/types"

	"banking-app/internal/events"
)

type Client struct {
	sqs      *sqs.Client
	queueURL string
	dlqURL   string
}

func New(ctx context.Context, queueURL, dlqURL string) (*Client, error) {
	cfg, err := config.LoadDefaultConfig(ctx)
	if err != nil {
		return nil, fmt.Errorf("loading AWS config: %w", err)
	}

	return &Client{
		sqs:      sqs.NewFromConfig(cfg),
		queueURL: queueURL,
		dlqURL:   dlqURL,
	}, nil
}

// Publish sends an event to the main queue. It's used by the API as a
// best-effort side effect: a failure here is logged by the caller but never
// fails the underlying read.
func (c *Client) Publish(ctx context.Context, event events.Event) error {
	body, err := event.Marshal()
	if err != nil {
		return fmt.Errorf("marshal event: %w", err)
	}

	_, err = c.sqs.SendMessage(ctx, &sqs.SendMessageInput{
		QueueUrl:    aws.String(c.queueURL),
		MessageBody: aws.String(string(body)),
	})
	if err != nil {
		return fmt.Errorf("send message: %w", err)
	}
	return nil
}

// Receive long-polls the main queue for up to 10 messages.
func (c *Client) Receive(ctx context.Context) ([]types.Message, error) {
	out, err := c.sqs.ReceiveMessage(ctx, &sqs.ReceiveMessageInput{
		QueueUrl:            aws.String(c.queueURL),
		MaxNumberOfMessages: 10,
		WaitTimeSeconds:     20,
	})
	if err != nil {
		return nil, fmt.Errorf("receive message: %w", err)
	}
	return out.Messages, nil
}

// Delete acknowledges a message, removing it from the main queue.
func (c *Client) Delete(ctx context.Context, receiptHandle string) error {
	_, err := c.sqs.DeleteMessage(ctx, &sqs.DeleteMessageInput{
		QueueUrl:      aws.String(c.queueURL),
		ReceiptHandle: aws.String(receiptHandle),
	})
	if err != nil {
		return fmt.Errorf("delete message: %w", err)
	}
	return nil
}

// SendToDLQ routes a message the consumer has identified as permanently
// unprocessable straight to the dead-letter queue, without waiting for the
// redrive policy's max-receive-count to be exhausted first.
func (c *Client) SendToDLQ(ctx context.Context, body, reason string) error {
	_, err := c.sqs.SendMessage(ctx, &sqs.SendMessageInput{
		QueueUrl:    aws.String(c.dlqURL),
		MessageBody: aws.String(body),
		MessageAttributes: map[string]types.MessageAttributeValue{
			"reason": {
				DataType:    aws.String("String"),
				StringValue: aws.String(reason),
			},
		},
	})
	if err != nil {
		return fmt.Errorf("send to dlq: %w", err)
	}
	return nil
}
