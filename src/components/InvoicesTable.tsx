import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
    Table,
    TableBody,
    TableCell,
    TableHead,
    TableHeader,
    TableRow,
} from "@/components/ui/table";
import { InvoiceData } from '@/payments/AbstractPaymentGateway';
import { formatCurrency } from '@/utils/formatCurrency';
import { formatDate } from '@/utils/formatDate';

interface InvoicesTableProps {
    invoices: InvoiceData[];
}

export function InvoicesTable({ invoices }: InvoicesTableProps) {
    return (
        <Table>
            <TableHeader>
                <TableRow>
                    <TableHead>Invoice ID</TableHead>
                    <TableHead>Date</TableHead>
                    <TableHead>Amount</TableHead>
                    <TableHead>Status</TableHead>
                    <TableHead>Product</TableHead>
                    <TableHead>Actions</TableHead>
                </TableRow>
            </TableHeader>
            <TableBody>
                {invoices.map((invoice) => (
                    <TableRow key={invoice.gateway_invoice_id}>
                        <TableCell className="font-medium">{invoice.gateway_invoice_id}</TableCell>
                        <TableCell>{formatDate(invoice.created_at)}</TableCell>
                        <TableCell>{formatCurrency(invoice.amount, invoice.currency)}</TableCell>
                        <TableCell>
                            <Badge variant={getStatusVariant(invoice.status)}>{invoice.status}</Badge>
                        </TableCell>
                        <TableCell>{invoice.billing_products?.name || 'N/A'}</TableCell>
                        <TableCell>
                            {invoice.hosted_invoice_url && (
                                <Button variant="outline" size="sm" asChild>
                                    <a href={invoice.hosted_invoice_url} target="_blank" rel="noopener noreferrer">
                                        View Invoice
                                    </a>
                                </Button>
                            )}
                        </TableCell>
                    </TableRow>
                ))}
            </TableBody>
        </Table>
    );
}

function getStatusVariant(status: string): "default" | "secondary" | "destructive" | "outline" {
    switch (status.toLowerCase()) {
        case 'paid':
            return 'default';
        case 'open':
            return 'secondary';
        case 'void':
        case 'uncollectible':
            return 'destructive';
        default:
            return 'outline';
    }
}
