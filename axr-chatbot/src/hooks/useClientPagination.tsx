import { clamp } from "@utils/utiliyFunctions";
import { useMemo, useState } from "react";

type TPaginationProps = {
  items: any[];
  itemsPerPage: number;
};

const useClientPagination = ({ items, itemsPerPage }: TPaginationProps) => {
  const [currentPage, setCurrentPage] = useState(0);

  const totalPages = Math.ceil(items.length / itemsPerPage);

  const total = items.length;

  const currentItems = useMemo(() => {
    return items.slice(
      currentPage * itemsPerPage,
      currentPage + 1 * itemsPerPage
    );
  }, [currentPage, items, itemsPerPage]);

  const navigateNextPage = () => {
    setPage(currentPage + 1);
  };

  const navigatePreviousPage = () => {
    setPage(currentPage - 1);
  };

  const setPage = (pageNumber: number) => {
    pageNumber = clamp(pageNumber, 0, totalPages - 1);
    setCurrentPage(pageNumber);
  };

  return {
    currentPage,
    totalPages,
    currentItems,
    total,
    navigateNextPage,
    navigatePreviousPage,
    setPage,
  };
};

export default useClientPagination;
