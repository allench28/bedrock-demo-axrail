import logo from "@assets/images/logo.png";

const SiteHeader = () => {
  return (
    <div className="flex flex-row justify-between items-center w-full h-[60px] px-4 py-2">
      <img src={logo} className="h-full aspect-square object-contain" />
    </div>
  );
};

export default SiteHeader;
