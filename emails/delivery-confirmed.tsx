import { Body } from '@react-email/body';
import { Container } from '@react-email/container';
import { Head } from '@react-email/head';
import { Heading } from '@react-email/heading';
import { Hr } from '@react-email/hr';
import { Html } from '@react-email/html';
import { Link } from '@react-email/link';
import { Text } from '@react-email/text';
import React from 'react';

interface DeliveryConfirmedProps {
  customerName: string;
  orderNumber: string;
  orderLink: string;
  supportEmail: string;
  storeName: string;
}

const DeliveryConfirmed: React.FC<DeliveryConfirmedProps> = ({
  customerName,
  orderNumber,
  orderLink,
  supportEmail,
  storeName,
}) => {
  return (
    <Html>
      <Head />
      <Body style={bodyStyle}>
        <Container style={containerStyle}>
          <Heading style={headingStyle}>Your package was delivered</Heading>
          <Hr style={hrStyle} />
          <Text style={textStyle}>Hi {customerName},</Text>
          <Text style={textStyle}>
            We hope you're enjoying your purchase! Order #{orderNumber} has been delivered. You can review your order here:
          </Text>
          <Link href={orderLink} style={linkStyle}>View Order Details</Link>
          <Hr style={hrStyle} />
          <Text style={textStyle}>
            Need assistance? Contact <Link href={`mailto:${supportEmail}`} style={linkStyle}>{supportEmail}</Link>.
          </Text>
          <Text style={signatureStyle}>Thank you for choosing {storeName}</Text>
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
DeliveryConfirmed.PreviewProps = {
  customerName: 'Jane Doe',
  orderNumber: '123456',
  orderLink: 'https://example.com/orders/123456',
  supportEmail: 'support@example.com',
  storeName: 'Awesome Store',
};

export default DeliveryConfirmed;
