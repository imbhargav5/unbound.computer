"use client"
import { Button } from '@/components/ui/button';
import html2canvas from 'html2canvas';
import jsPDF from "jspdf";
import { Upload } from 'lucide-react';
import { useTheme } from 'next-themes';
import { useState } from 'react';

export const WorkspaceExportPDF = () => {
  const [loading, setLoading] = useState(false);
  const [disabled, setDisabled] = useState(false);

  const { theme } = useTheme()

  const exportPDF = () => {
    const input = document.getElementById("export-container");

    if (input && input.offsetHeight > 0 && input.offsetWidth > 0) {
      setDisabled(true);
      setLoading(true);
      html2canvas(input, {
        scale: 2, backgroundColor: theme === "dark" ? "#020817" : "#fff",
      })
        .then((canvas) => {

          const imgData = canvas.toDataURL("image/png");
          const pdf = new jsPDF({
            orientation: "portrait",

          });
          const imgProps = pdf.getImageProperties(imgData);
          const pdfWidth = pdf.internal.pageSize.getWidth();
          const pdfHeight = (imgProps.height * pdfWidth) / imgProps.width;
          pdf.addImage(imgData, "PNG", 0, 0, pdfWidth, pdfHeight);
          pdf.save("organization.pdf");
        })
        .finally(() => {
          setDisabled(false);
          setLoading(false);
        });
    } else {
      setDisabled(true);
      setLoading(false);
    }
  };
  return (
    <Button variant="ghost" onClick={exportPDF} className="mb-4 flex gap-2 items-center" disabled={disabled}>
      <Upload className='size-4' />
      {loading ? "Exporting..." : "Export PDF"}
    </Button>
  )
}
