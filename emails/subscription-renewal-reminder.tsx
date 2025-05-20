import { Body } from '@react-email/body';
import { Button } from '@react-email/button';
import { Container } from '@react-email/container';
import { Head } from '@react-email/head';
import { Heading } from '@react-email/heading';
import { Hr } from '@react-email/hr';
import { Html } from '@react-email/html';
import { Link } from '@react-email/link';
import { Text } from '@react-email/text';
import React from 'react';

interface SubscriptionRenewalReminderProps {
  userName: string;
  appName: string;
  renewalDate: Date;
  manageSubscriptionLink: string;
  supportEmail: string;
}

const SubscriptionRenewalReminder: React.FC<SubscriptionRenewalReminderProps> = ({
  userName,
  appName,
  renewalDate,
  manageSubscriptionLink,
  supportEmail,
}) => {
  return (
    <Html>
      <Head />
      <Body style={bodyStyle}>
        <Container style={containerStyle}>
          <Heading style={headingStyle}>Your subscription renews soon</Heading>
          <Hr style={hrStyle} />
          <Text style={textStyle}>Dear {userName},</Text>
          <Text style={textStyle}>
            This is a friendly reminder that your {appName} subscription will automatically renew on{' '}
            {renewalDate.toLocaleDateString()}.
          </Text>
          <Text style={textStyle}>
            If you need to update your billing information or cancel your subscription, please visit the link below:
          </Text>
          <Button href={manageSubscriptionLink} style={buttonStyle}>
            Manage Subscription
          </Button>
          <Hr style={hrStyle} />
          <Text style={textStyle}>
            For any questions, contact our support team at{' '}
            <Link href={`mailto:${supportEmail}`} style={linkStyle}>
              {supportEmail}
            </Link>
            .
          </Text>
          <Text style={signatureStyle}>The {appName} Team</Text>
        </Container>
      </Body>
    </Html>
  );
};

const bodyStyle: React.CSSProperties = {
  backgroundColor: '#f6f9fc',
  fontFamily: '-apple-system,BlinkMacSystemFont,\"Segoe UI\",Roboto,\"Helvetica Neue\",Ubuntu,sans-serif',
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
  backgroundColor: '#007bff',
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

const linkStyle: React.CSSProperties = {
  color: '#0366d6',
  textDecoration: 'none',
};

const signatureStyle: React.CSSProperties = {
  fontSize: '16px',
  color: '#4a4a4a',
  fontWeight: 'bold',
};

// @ts-ignore
SubscriptionRenewalReminder.PreviewProps = {
  userName: 'John Doe',
  appName: 'AwesomeApp',
  renewalDate: new Date('2024-09-01'),
  manageSubscriptionLink: 'https://example.com/manage',
  supportEmail: 'support@example.com',
};

export default SubscriptionRenewalReminder;
