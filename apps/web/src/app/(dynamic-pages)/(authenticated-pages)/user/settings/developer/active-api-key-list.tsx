import { format } from "date-fns";
import moment from "moment";
import { PageHeading } from "@/components/page-heading";
import {
  Table as ShadcnTable,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from "@/components/ui/table";
import { T } from "@/components/ui/typography-ui";
import { getActiveDeveloperKeys } from "@/data/user/unkey";
import { ConfirmRevokeTokenDialog } from "./confirm-revoke-token-dialog";

export async function ActiveApiKeyList() {
  const activeDeveloperKeys = await getActiveDeveloperKeys();
  const heading = (
    <PageHeading
      subTitle="Below is the list of your API keys with their details. You can use your API keys to access the platform programmatically. Eg: Zapier, Integromat, Make etc."
      title="Active API Keys"
      titleClassName="text-lg"
    />
  );

  if (activeDeveloperKeys.length) {
    return (
      <div className="max-w-4xl space-y-8">
        {heading}
        <ShadcnTable>
          <TableHeader>
            <TableRow>
              <TableHead className="w-[120px]">API Key</TableHead>
              <TableHead className="w-[140px]">Generated On</TableHead>
              <TableHead className="w-[140px]">Expires In</TableHead>
              <TableHead className="w-[80px]">Actions</TableHead>
            </TableRow>
          </TableHeader>
          <TableBody>
            {activeDeveloperKeys.map((apiKey) => (
              <TableRow key={apiKey.key_id}>
                <TableCell className="font-medium">
                  {apiKey.masked_key}
                </TableCell>
                <TableCell className="font-medium">
                  {format(new Date(apiKey.created_at), "PPP")}
                </TableCell>

                <TableCell>
                  {apiKey.expires_at
                    ? moment(apiKey.expires_at).format("LL")
                    : "No expiry"}
                </TableCell>
                <TableCell>
                  <ConfirmRevokeTokenDialog keyId={apiKey.key_id} />
                </TableCell>
              </TableRow>
            ))}
          </TableBody>
        </ShadcnTable>
      </div>
    );
  }
  return (
    <div className="max-w-sm">
      {heading}
      <T.Subtle>No active API keys.</T.Subtle>
    </div>
  );
}
