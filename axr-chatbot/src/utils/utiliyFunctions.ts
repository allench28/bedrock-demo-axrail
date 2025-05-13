export const isLocalHost = () => {
  return window.location.href.includes("localhost");
};

export const DownloadFile = ({
  url,
  overrideFilename,
}: {
  url: string;
  overrideFilename?: string;
}) => {
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = overrideFilename ?? "";
  anchor.target = "_blank";
  document.body.appendChild(anchor);
  anchor.click();
  document.body.removeChild(anchor);
};

export const clamp = (value: number, min: number, max: number) => {
  return Math.min(Math.max(value, min), max);
};

export const wait = (ms: number) => {
  return new Promise((resolve) => setTimeout(resolve, ms));
};
