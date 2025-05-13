import SiteHeader from "./SiteHeader";

const SiteContainer = ({ children }) => {
  return (
    <div className="flex flex-col items-start justify-center w-full h-full bg-[#f5f9ff]">
      <SiteHeader />
      {children}
    </div>
  );
};

export default SiteContainer;
