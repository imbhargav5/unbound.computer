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

interface ScheduledMaintenanceNoticeProps {
  userName: string;
  appName: string;
  maintenanceStart: Date;
  maintenanceEnd: Date;
  detailsLink: string;
  supportEmail: string;
}

const ScheduledMaintenanceNotice: React.FC<ScheduledMaintenanceNoticeProps> = ({
  userName,
  appName,
  maintenanceStart,
  maintenanceEnd,
  detailsLink,
  supportEmail,
}) => {
  return (
    <Html>
      <Head />
      <Body style={bodyStyle}>
        <Container style={containerStyle}>
          <Heading style={headingStyle}>Upcoming Scheduled Maintenance</Heading>
          <Hr style={hrStyle} />
          <Text style={textStyle}>Hello {userName},</Text>
          <Text style={textStyle}>
            We will be performing scheduled maintenance on {appName} from{' '}
            {maintenanceStart.toLocaleString()} to {maintenanceEnd.toLocaleString()}.
          </Text>
          <Text style={textStyle}>
            During this time the service may be unavailable. You can learn more about the maintenance here:
          </Text>
          <Button href={detailsLink} style={buttonStyle}>View Details</Button>
          <Hr style={hrStyle} />
          <Text style={textStyle}>
            If you have any concerns, please contact <Link href={`mailto:${supportEmail}`} style={linkStyle}>{supportEmail}</Link>.
          </Text>
          <Text style={signatureStyle}>Thank you for your understanding,<br />The {appName} Team</Text>
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
  backgroundColor: '#ff9800',
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
ScheduledMaintenanceNotice.PreviewProps = {
  userName: 'John Doe',
  appName: 'AwesomeApp',
  maintenanceStart: new Date('2024-07-15T02:00:00Z'),
  maintenanceEnd: new Date('2024-07-15T04:00:00Z'),
  detailsLink: 'https://example.com/maintenance',
  supportEmail: 'support@example.com',
};

export default ScheduledMaintenanceNotice;
