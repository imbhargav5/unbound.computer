"use client"

import dynamic from 'next/dynamic';

const OrganizationExportPDF = dynamic(() => import('./WorkspaceExportPDF').then(m => m.WorkspaceExportPDF));

export function ExportPDF() {
  return <OrganizationExportPDF />;
}
