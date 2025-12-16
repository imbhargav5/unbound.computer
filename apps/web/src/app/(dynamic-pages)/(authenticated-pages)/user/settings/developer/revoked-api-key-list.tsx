import { format } from "date-fns";
import { PageHeading } from "@/components/page-heading";
import {
  Table as ShadcnTable,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { getRevokedApiKeyList } from "@/data/user/unkey";

export async function RevokedApiKeyList() {
  const revokedApiKeyList = await getRevokedApiKeyList();

  if (!revokedApiKeyList.length) {
    return <p>No revoked keys</p>;
  }

  const heading = (
    <PageHeading
      subTitle="Below is the list of your revoked API keys with their details."
      title="Revoked API Keys"
      titleClassName="text-lg"
    />
  );

  return (
    <div className="max-w-4xl space-y-8">
      {heading}
      <div className="space-y-2">
        <ShadcnTable>
          <TableHeader>
            <TableRow>
              <TableHead className="w-[120px]">API Key</TableHead>
              <TableHead className="w-[140px]">Generated On</TableHead>
              <TableHead className="w-[140px]">Status</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {revokedApiKeyList.map((apiKey) => (
              <TableRow key={apiKey.key_id}>
                <TableCell className="font-medium">
                  {apiKey.masked_key}
                </TableCell>
                <TableCell>
                  {format(new Date(apiKey.created_at), "PPP")}
                </TableCell>
                <TableCell>Revoked</TableCell>
              </TableRow>
            ))}
          </TableBody>
        </ShadcnTable>
      </div>
    </div>
  );
}
