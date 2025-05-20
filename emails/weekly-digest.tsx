import { Body } from '@react-email/body';
import { Button } from '@react-email/button';
import { Container } from '@react-email/container';
import { Head } from '@react-email/head';
import { Heading } from '@react-email/heading';
import { Hr } from '@react-email/hr';
import { Html } from '@react-email/html';
import { Text } from '@react-email/text';
import React from 'react';

interface WeeklyDigestProps {
  digestLink: string;
  blogName: string;
  subscriberName: string;
}

const WeeklyDigest: React.FC<WeeklyDigestProps> = ({
  digestLink,
  blogName,
  subscriberName,
}) => {
  return (
    <Html>
      <Head />
      <Body style={bodyStyle}>
        <Container style={containerStyle}>
          <Heading style={headingStyle}>Your weekly digest</Heading>
          <Hr style={hrStyle} />
          <Text style={textStyle}>Hi {subscriberName},</Text>
          <Text style={textStyle}>Here are the latest posts from {blogName}.</Text>
          <Button href={digestLink} style={buttonStyle}>Read Digest</Button>
          <Hr style={hrStyle} />
          <Text style={signatureStyle}>Thanks for staying up to date!</Text>
        </Container>
      </Body>
    </Html>
  );
};

const bodyStyle: React.CSSProperties = {
  backgroundColor: '#f6f9fc',
  fontFamily: '-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,"Helvetica Neue",Ubuntu,sans-serif',
  lineHeight: 1.5,
};

const containerStyle: React.CSSProperties = {
  backgroundColor: '#ffffff',
  margin: '0 auto',
  padding: '40px 20px',
  maxWidth: '600px',
  borderRadius: '8px',
  boxShadow: '0 4px 6px rgba(0, 0, 0, 0.1)',
};

const headingStyle: React.CSSProperties = {
  fontSize: '24px',
  fontWeight: 'bold',
  color: '#333',
  textAlign: 'center',
  margin: '20px 0',
};

const hrStyle: React.CSSProperties = {
  borderColor: '#e6ebf1',
  margin: '20px 0',
};

const textStyle: React.CSSProperties = {
  fontSize: '16px',
  color: '#4a4a4a',
  marginBottom: '20px',
};

const buttonStyle: React.CSSProperties = {
  backgroundColor: '#0070f3',
  color: '#ffffff',
  borderRadius: '4px',
  fontSize: '16px',
  fontWeight: 'bold',
  textDecoration: 'none',
  textAlign: 'center',
  display: 'inline-block',
  padding: '12px 20px',
  margin: '20px 0',
};

const signatureStyle: React.CSSProperties = {
  fontSize: '16px',
  color: '#4a4a4a',
  fontWeight: 'bold',
};

// @ts-ignore
WeeklyDigest.PreviewProps = {
  digestLink: 'https://example.com/digest',
  blogName: 'Awesome Blog',
  subscriberName: 'Jane Doe',
};

export default WeeklyDigest;
